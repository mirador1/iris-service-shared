#!/usr/bin/env bash
# Install GitLab Agent for Kubernetes (mirador) into the demo GKE cluster.
# Run AFTER: bin/cluster/demo/up.sh has finished + kubectl context is set.
set -euo pipefail

TOKEN_FILE="/tmp/gitlab-agent-mirador.token"
[ -f "$TOKEN_FILE" ] || { echo "❌ token file missing: $TOKEN_FILE"; exit 1; }
TOKEN="$(cat "$TOKEN_FILE")"

# Use gke-gcloud-auth-plugin (required for GKE 1.26+)
export USE_GKE_GCLOUD_AUTH_PLUGIN=True

# Switch kubectl to the new cluster
gcloud container clusters get-credentials mirador-prod \
  --region europe-west1 \
  --project project-8d6ea68c-33ac-412b-8aa

echo "▶️  Installing GitLab Agent 'mirador' via Helm…"
helm repo add gitlab https://charts.gitlab.io 2>/dev/null || true
helm repo update gitlab

helm upgrade --install mirador gitlab/gitlab-agent \
  --namespace gitlab-agent-mirador --create-namespace \
  --set image.tag=v17.6.0 \
  --set config.token="$TOKEN" \
  --set config.kasAddress=wss://kas.gitlab.com

echo ""
echo "▶️  Verifying Agent connection…"
kubectl wait --for=condition=Available --timeout=180s \
  deployment/mirador -n gitlab-agent-mirador
kubectl get pods -n gitlab-agent-mirador

echo ""
echo "✅ Agent installed. Check https://gitlab.com/mirador1/mirador-service/-/clusters"
echo "   Agent should appear as 'mirador' with status 'Connected' within ~30 s."
