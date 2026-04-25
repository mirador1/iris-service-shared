#!/usr/bin/env bash
# =============================================================================
# bin/cluster/demo/install-gmp-frontend.sh — deploy the GMP query frontend.
#
# What this solves: GKE Autopilot disables hostPath and locks kube-system,
# so the standard `kube-prometheus-stack` chart CANNOT create the `kubelet`
# Service needed to scrape cAdvisor (per-pod CPU/memory). OpenLens's
# "Metrics" tab then shows empty.
#
# Google Managed Prometheus (GMP) IS already collecting cAdvisor + kubelet
# metrics on Autopilot (managedPrometheusConfig.enabled=True) — but into
# Cloud Monitoring, not a local Prometheus port. The GMP `frontend` is a
# PromQL-compatible proxy that lets any Prometheus client (OpenLens,
# Grafana, k9s) query GMP as if it were a local Prometheus.
#
# Architecture:
#   OpenLens → svc/gmp-frontend:9090 → Cloud Monitoring API → GMP scrapes
#              (Prometheus-compatible query endpoint, auth via Workload Identity)
#
# After running this script:
#   - OpenLens auto-detects `monitoring/gmp-frontend` via the
#     `app.kubernetes.io/name=prometheus` label and shows full pod metrics.
#   - `kubectl port-forward -n monitoring svc/gmp-frontend 9091:9090` + open
#     http://localhost:9091 gives a Prometheus UI against Cloud Monitoring.
#
# See also: docs/ops/runbooks/gmp-frontend-openlens.md for the why + the
# alternatives evaluated (A: kube-prom-stack only, C: GCP Console, D: Grafana,
# E: GKE Standard, F: Lens Desktop paid) and why option B (this script) won.
# =============================================================================
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-project-8d6ea68c-33ac-412b-8aa}"
GSA="gmp-frontend-viewer"
GSA_EMAIL="${GSA}@${PROJECT_ID}.iam.gserviceaccount.com"

echo "▶️  [1/4] Creating GCP service account $GSA (idempotent)…"
if ! gcloud iam service-accounts describe "$GSA_EMAIL" --project="$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$GSA" \
    --project="$PROJECT_ID" \
    --display-name="GMP frontend query proxy (Autopilot bridge)"
fi

echo "▶️  [2/4] Granting monitoring.viewer + stackdriver metadata reader…"
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GSA_EMAIL" \
  --role="roles/monitoring.viewer" \
  --condition=None >/dev/null
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$GSA_EMAIL" \
  --role="roles/stackdriver.resourceMetadata.viewer" \
  --condition=None >/dev/null

echo "▶️  [3/4] Workload Identity binding (K8s SA monitoring/gmp-frontend → GCP SA)…"
gcloud iam service-accounts add-iam-policy-binding "$GSA_EMAIL" \
  --project="$PROJECT_ID" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[monitoring/gmp-frontend]" >/dev/null

echo "▶️  [4/4] Deploying frontend pod (image v0.15.3-gke.0)…"
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gmp-frontend
  namespace: monitoring
  annotations:
    iam.gke.io/gcp-service-account: ${GSA_EMAIL}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gmp-frontend
  namespace: monitoring
  labels:
    app: gmp-frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gmp-frontend
  template:
    metadata:
      labels:
        app: gmp-frontend
    spec:
      serviceAccountName: gmp-frontend
      automountServiceAccountToken: true
      containers:
      - name: frontend
        image: gke.gcr.io/prometheus-engine/frontend:v0.15.3-gke.0
        args:
        - "--web.listen-address=:9090"
        - "--query.project-id=${PROJECT_ID}"
        ports:
        - name: web
          containerPort: 9090
        readinessProbe:
          httpGet:
            path: /-/ready
            port: web
        livenessProbe:
          httpGet:
            path: /-/healthy
            port: web
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: gmp-frontend
  namespace: monitoring
  labels:
    # OpenLens auto-detects Prometheus via this label. Keep unique —
    # unlabel the kube-prometheus-stack Service if you run both. See
    # docs/ops/runbooks/gmp-frontend-openlens.md.
    app.kubernetes.io/name: prometheus
spec:
  selector:
    app: gmp-frontend
  ports:
  - name: http
    port: 9090
    targetPort: 9090
  type: ClusterIP
EOF

echo "▶️  Waiting for GMP frontend ready…"
kubectl wait --for=condition=Available --timeout=180s deployment/gmp-frontend -n monitoring

echo ""
echo "✅ GMP frontend deployed."
echo ""
echo "Verify from laptop:"
echo "  kubectl port-forward -n monitoring svc/gmp-frontend 9091:9090"
echo "  curl http://localhost:9091/-/ready"
echo "  curl 'http://localhost:9091/api/v1/query?query=up' | jq"
echo ""
echo "Configure OpenLens:"
echo "  1. Close+reopen the cluster tab so auto-detect rescans services."
echo "  2. If metrics still missing, Cluster Settings → Metrics → Prometheus"
echo "     Service: monitoring/gmp-frontend:9090, type 'prometheus-operator'."
