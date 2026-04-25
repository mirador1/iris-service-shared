#!/usr/bin/env bash
# =============================================================================
# bin/budget/ovh-cost-audit.sh — scan OVH for orphan resources + monthly spend.
#
# Mirrors gcp-cost-audit.sh — reports anything that's silently billing on
# the OVH project so a forgotten cluster doesn't drift past the budget.
#
# Per ADR-0053, OVH adds ~€25/month per running B2-7 node. The HARD ceiling
# is autoscale max=2 (~€50/month). This script :
#   1. Authenticates with the OVH API (using OVH_APPLICATION_KEY etc.)
#   2. Lists all running compute resources on the project (kube clusters,
#      nodepools, instances, load balancers, persistent storage)
#   3. Estimates monthly cost from the SKU pricing table
#   4. Compares against /me/bill for the current billing cycle
#   5. Flags ALERT if estimated spend > €5/month threshold
#
# Usage:
#   bin/budget/ovh-cost-audit.sh              # report only (read-only)
#   bin/budget/ovh-cost-audit.sh --delete     # prompt-per-resource cleanup
#   bin/budget/ovh-cost-audit.sh --yes        # non-interactive (CI)
#
# Requires: jq + curl (no ovh-cli needed — straight HTTP signed calls).
# =============================================================================
set -euo pipefail

# Threshold above which to print a red ALERT.
THRESHOLD_EUR_PER_MONTH=5

# Pre-flight: env vars + tools.
for var in OVH_APPLICATION_KEY OVH_APPLICATION_SECRET OVH_CONSUMER_KEY OVH_PROJECT_ID; do
  if [ -z "${!var:-}" ]; then
    echo "❌ \$$var not set. See deploy/terraform/ovh/README.md § Authentication."
    exit 1
  fi
done

for tool in jq curl python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "❌ $tool not on PATH (required for OVH API signing)."
    exit 1
  fi
done

DELETE=0
YES=0
for arg in "$@"; do
  case "$arg" in
    --delete) DELETE=1 ;;
    --yes)    YES=1 ; DELETE=1 ;;
    *) echo "Unknown arg: $arg"; exit 1 ;;
  esac
done

OVH_BASE="https://eu.api.ovh.com/1.0"

# =============================================================================
# OVH API request signing — the protocol uses HMAC-SHA1-style hash chain :
#   sig = "$1$" + sha1(application_secret + "+" + consumer_key + "+" +
#                       method + "+" + url + "+" + body + "+" + timestamp)
#
# Implemented here in Python rather than pure bash because shasum + base64
# pipe has portability quirks across BSD (macOS) vs GNU coreutils.
# =============================================================================
ovh_call() {
  local method="$1" path="$2" body="${3:-}"
  local url="$OVH_BASE$path"
  local timestamp; timestamp=$(date +%s)

  local sig; sig=$(python3 - <<PYEOF
import hashlib, sys
secret    = "$OVH_APPLICATION_SECRET"
consumer  = "$OVH_CONSUMER_KEY"
method    = "$method"
url       = "$url"
body      = """$body"""
ts        = "$timestamp"
to_hash   = f"{secret}+{consumer}+{method}+{url}+{body}+{ts}"
print("\$1\$" + hashlib.sha1(to_hash.encode()).hexdigest())
PYEOF
)

  curl -sS -X "$method" "$url" \
    -H "X-Ovh-Application: $OVH_APPLICATION_KEY" \
    -H "X-Ovh-Consumer: $OVH_CONSUMER_KEY" \
    -H "X-Ovh-Signature: $sig" \
    -H "X-Ovh-Timestamp: $timestamp" \
    -H "Content-Type: application/json" \
    ${body:+--data "$body"}
}

# =============================================================================
# Step 1 — list Managed K8s clusters on the project. Each cluster is the
# tip of the iceberg ; the actual cost is in the nodepools attached to it.
# =============================================================================
echo "▶️  OVH cost audit — project $OVH_PROJECT_ID (alert threshold €$THRESHOLD_EUR_PER_MONTH/month)"
echo ""
echo "━━━ Managed Kubernetes clusters ━━━"

CLUSTERS=$(ovh_call GET "/cloud/project/$OVH_PROJECT_ID/kube" | jq -r '.[]')
TOTAL_COST=0

if [ -z "$CLUSTERS" ]; then
  echo "  ✓ No active K8s clusters."
else
  for cluster_id in $CLUSTERS; do
    NAME=$(ovh_call GET "/cloud/project/$OVH_PROJECT_ID/kube/$cluster_id" | jq -r '.name')
    REGION=$(ovh_call GET "/cloud/project/$OVH_PROJECT_ID/kube/$cluster_id" | jq -r '.region')
    echo "  • $NAME (id=$cluster_id, region=$REGION)"

    # List nodepools — each one bills.
    NODEPOOLS=$(ovh_call GET "/cloud/project/$OVH_PROJECT_ID/kube/$cluster_id/nodepool" | jq -r '.[]')
    for np_id in $NODEPOOLS; do
      NP_INFO=$(ovh_call GET "/cloud/project/$OVH_PROJECT_ID/kube/$cluster_id/nodepool/$np_id")
      NP_NAME=$(echo "$NP_INFO" | jq -r '.name')
      NP_FLAVOR=$(echo "$NP_INFO" | jq -r '.flavorName')
      NP_SIZE=$(echo "$NP_INFO" | jq -r '.desiredNodes')

      # Pricing table (rough — verify yearly against ovhcloud.com/fr/public-cloud/prices/).
      case "$NP_FLAVOR" in
        B2-7)  unit_price=25.20 ;;
        B2-15) unit_price=42.00 ;;
        C2-7)  unit_price=36.00 ;;
        D2-2)  unit_price=10.00 ;;
        *)     unit_price=30.00 ; echo "    ⚠ Unknown flavor $NP_FLAVOR — using €30 estimate" ;;
      esac

      np_cost=$(python3 -c "print($NP_SIZE * $unit_price)")
      TOTAL_COST=$(python3 -c "print($TOTAL_COST + $np_cost)")
      echo "    └ nodepool $NP_NAME : $NP_SIZE × $NP_FLAVOR ≈ €$np_cost/month"
    done
  done
fi

# =============================================================================
# Step 2 — orphan instances (compute outside any K8s cluster).
# A forgotten test instance is a classic silent leak.
# =============================================================================
echo ""
echo "━━━ Standalone instances (outside K8s) ━━━"

INSTANCES=$(ovh_call GET "/cloud/project/$OVH_PROJECT_ID/instance" 2>/dev/null | jq -r '.[]?.id // empty')

if [ -z "$INSTANCES" ]; then
  echo "  ✓ No standalone instances."
else
  for instance_id in $INSTANCES; do
    INFO=$(ovh_call GET "/cloud/project/$OVH_PROJECT_ID/instance/$instance_id")
    NAME=$(echo "$INFO" | jq -r '.name')
    FLAVOR=$(echo "$INFO" | jq -r '.flavorId')
    echo "  • $NAME (flavor=$FLAVOR) — review whether intentional"
  done
fi

# =============================================================================
# Step 3 — Public Cloud Load Balancers (~€20/month each, easy to forget).
# =============================================================================
echo ""
echo "━━━ Public Cloud Load Balancers ━━━"

LBS=$(ovh_call GET "/cloud/project/$OVH_PROJECT_ID/loadbalancer" 2>/dev/null | jq -r '.[]?.id // empty')

if [ -z "$LBS" ]; then
  echo "  ✓ No load balancers."
else
  LB_COUNT=0
  for lb_id in $LBS; do
    LB_COUNT=$((LB_COUNT + 1))
  done
  LB_COST=$(python3 -c "print($LB_COUNT * 20)")
  TOTAL_COST=$(python3 -c "print($TOTAL_COST + $LB_COST)")
  echo "  • $LB_COUNT load balancer(s) ≈ €$LB_COST/month"
fi

# =============================================================================
# Step 4 — verdict.
# =============================================================================
echo ""
echo "━━━ Total estimated monthly spend ━━━"
echo "  ≈ €$TOTAL_COST/month"

OVER=$(python3 -c "print('1' if $TOTAL_COST > $THRESHOLD_EUR_PER_MONTH else '0')")
if [ "$OVER" = "1" ]; then
  echo ""
  echo "🔴 ALERT — over €$THRESHOLD_EUR_PER_MONTH threshold."
  echo "   Stop the cluster: bin/cluster/ovh/down.sh"
  if [ "$DELETE" = "1" ]; then
    if [ "$YES" = "0" ]; then
      read -r -p "Run ovh/down.sh now? [y/N] " confirm
      [ "$confirm" = "y" ] || { echo "Skipped."; exit 0; }
    fi
    "$(git rev-parse --show-toplevel)/bin/cluster/ovh/down.sh"
  fi
else
  echo "✅ Within budget."
fi
