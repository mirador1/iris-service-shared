#!/usr/bin/env bash
# =============================================================================
# bin/budget/gcp-cost-audit.sh — scan the GCP project for silent monthly costs.
#
# Why this exists. The ADR-0022 ephemeral-cluster pattern assumes the
# cluster lifecycle (create + 2h demo + destroy) produces ~€2/month. That
# number holds only if the destroy cleanly reclaims every resource. GKE +
# GCE don't guarantee that — the classic trap is PVC disks that outlive
# the cluster because terraform destroyed the node pool before `kubectl
# delete pvc` had a chance to run. Each survivor silently bills
# €0.048/GB/month as a Balanced persistent disk for as long as nobody
# notices.
#
# This script lists every resource class that commonly produces silent
# cost, estimates monthly €, and offers to delete whatever is orphaned.
# Designed to be rerun monthly (cron) or after every demo.
#
# Usage:
#   bin/budget/gcp-cost-audit.sh              # report only (safe, read-only)
#   bin/budget/gcp-cost-audit.sh --delete     # prompt-per-class deletion
#   bin/budget/gcp-cost-audit.sh --yes        # non-interactive purge (CI)
#
# bin/cluster/demo/down.sh already embeds the PVC cleanup for the happy path.
# This script is the safety net + the answer to "what am I paying now?"
# when demo-down wasn't run or crashed mid-flight.
# =============================================================================

set -u

PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
if [[ -z "$PROJECT" ]]; then
  echo "❌  no gcloud project set — run: gcloud config set project <id>"
  exit 1
fi

DELETE=0
YES=0
for arg in "$@"; do
  case "$arg" in
    --delete) DELETE=1 ;;
    --yes)    DELETE=1; YES=1 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
  esac
done

echo "🔍  GCP cost audit — project $PROJECT  ($(date +%H:%M:%S))"
echo

# ── Helpers ─────────────────────────────────────────────────────────────────

confirm() {
  [[ "$YES" == "1" ]] && return 0
  read -r -p "    Delete these? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]]
}

# ── 1. Orphaned PVC disks (the big one) ─────────────────────────────────────
echo "📀  Persistent disks — orphaned PVCs (PD-balanced ≈ €0.048/GB/mo)"
orphans=$(gcloud compute disks list --project="$PROJECT" \
  --filter="-users:* AND name:pvc-*" \
  --format="value(name,zone.basename(),sizeGb)" 2>/dev/null)
if [[ -z "$orphans" ]]; then
  echo "   ✓ none — cluster teardown is clean."
else
  total_gb=0
  while IFS=$'\t' read -r n z s; do
    printf "   - %-50s %-18s %3s GB\n" "$n" "$z" "$s"
    total_gb=$((total_gb + s))
  done <<< "$orphans"
  printf "   → %d GB total ≈ €%.2f/month\n" "$total_gb" "$(awk "BEGIN{printf \"%.2f\", $total_gb * 0.048}")"
  if [[ "$DELETE" == "1" ]] && confirm; then
    while IFS=$'\t' read -r n z s; do
      gcloud compute disks delete "$n" --zone="$z" --project="$PROJECT" --quiet >/dev/null 2>&1 && echo "    ✓ deleted $n"
    done <<< "$orphans"
  fi
fi
echo

# ── 2. Reserved static IPs not attached to anything (~€1.50/mo each) ────────
echo "🌐  Static IPs — reserved but unattached (≈ €1.50/IP/month)"
unattached_ips=$(gcloud compute addresses list --project="$PROJECT" \
  --filter="status=RESERVED" \
  --format="value(name,region.basename(),address)" 2>/dev/null)
if [[ -z "$unattached_ips" ]]; then
  echo "   ✓ none."
else
  echo "$unattached_ips" | while IFS=$'\t' read -r n r a; do
    printf "   - %-30s %-15s %s\n" "$n" "${r:-global}" "$a"
  done
fi
echo

# ── 3. Idle Cloud NAT gateways (~€1.20/mo each + egress) ────────────────────
echo "🚦  Cloud NAT gateways"
routers=$(gcloud compute routers list --project="$PROJECT" --format="value(name,region.basename())" 2>/dev/null)
if [[ -z "$routers" ]]; then
  echo "   ✓ none."
else
  echo "$routers" | while IFS=$'\t' read -r n r; do
    printf "   - %-30s %s (~€1.20/month + egress)\n" "$n" "$r"
  done
fi
echo

# ── 4. Load balancers / forwarding rules (varies but rarely free) ───────────
echo "⚖️   Forwarding rules / load balancers"
fwd=$(gcloud compute forwarding-rules list --project="$PROJECT" \
  --format="value(name,region.basename(),target.basename())" 2>/dev/null)
if [[ -z "$fwd" ]]; then
  echo "   ✓ none."
else
  echo "$fwd" | while IFS=$'\t' read -r n r t; do
    printf "   - %-30s %-15s → %s\n" "$n" "${r:-global}" "$t"
  done
fi
echo

# ── 5. Snapshots (cheap but grow unbounded under scheduled policies) ────────
echo "📸  Persistent disk snapshots (≈ €0.025/GB/mo)"
snapshots=$(gcloud compute snapshots list --project="$PROJECT" --format="value(name,diskSizeGb,creationTimestamp)" 2>/dev/null)
if [[ -z "$snapshots" ]]; then
  echo "   ✓ none."
else
  total_gb=0
  while IFS=$'\t' read -r n s c; do
    printf "   - %-40s %3s GB (%s)\n" "$n" "$s" "${c%T*}"
    total_gb=$((total_gb + s))
  done <<< "$snapshots"
  printf "   → %d GB ≈ €%.2f/month\n" "$total_gb" "$(awk "BEGIN{printf \"%.2f\", $total_gb * 0.025}")"
fi
echo

# ── 6. GKE cluster — up or not? (Autopilot pods bill ~€0.02/pod/hour) ──────
echo "☸️   GKE clusters (Autopilot billing: pods + PVs)"
clusters=$(gcloud container clusters list --project="$PROJECT" \
  --format="value(name,location,status,currentNodeCount)" 2>/dev/null)
if [[ -z "$clusters" ]]; then
  echo "   ⏸  no cluster provisioned — €0/hour."
else
  echo "$clusters" | while IFS=$'\t' read -r n l s nodes; do
    printf "   - %-20s %-18s status=%-8s nodes=%s\n" "$n" "$l" "$s" "${nodes:-0}"
  done
  echo "     → if demo is over, run: bin/cluster/demo/down.sh"
fi
echo

# ── 7. Artifact Registry size (cheap but drifts upward with each push) ──────
echo "📦  Artifact Registry repos (≈ €0.10/GB/mo storage + egress)"
# sizeInBytes isn't in the default format; ask explicitly.
gcloud artifacts repositories list --project="$PROJECT" \
  --format="table(name.basename():label=NAME,location,format,sizeInBytes.size(units_in=B,units_out=MB):label=SIZE_MB)" \
  2>/dev/null | head -20 || echo "   (artifact registry API not enabled or no repos)"
echo

# ── Summary ────────────────────────────────────────────────────────────────
cat <<EOF
Rerun monthly or add to a cron (macOS launchd or GitLab scheduled
pipeline against this repo). Typical idle target: <€1/month on an
ephemeral cluster project, provided demo-down runs after every demo.

Cron one-liner (monthly, silent delete):
  0 2 1 * *  cd $(cd "$(dirname "$0")/.." && pwd) && bin/budget/gcp-cost-audit.sh --yes
EOF
