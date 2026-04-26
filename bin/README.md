# `bin/` — Operational scripts inventory

Cross-cutting scripts for the [mirador1](https://gitlab.com/mirador1)
project family. Submoduled into `mirador-service-java` and
`mirador-service-python` under `infra/shared/bin/`. Run from the consuming
repo's path : `infra/shared/bin/<group>/<script>.sh`.

## `budget/` — Cost control

Cloud cost guardrails. Each script runs against a single provider ; pair
them with the matching launchd plists in `bin/launchd/`.

| Script | Purpose | Schedule |
|---|---|---|
| [`budget.sh`](budget/budget.sh) | GCP budget set / status / recreate via `gcloud billing budgets`. | Manual |
| [`gcp-cost-audit.sh`](budget/gcp-cost-audit.sh) | Last-7-day GCP spend by service. Catches forgotten resources. | Daily via cron |
| [`ovh-alert.sh`](budget/ovh-alert.sh) | OVH MTD spend alert (no native GCP-style budget API). Desktop notification when threshold crossed. | Daily via launchd |
| [`ovh-cost-audit.sh`](budget/ovh-cost-audit.sh) | OVH detailed cost breakdown (bills + projects). | Manual |
| [`budget-kill-deploy.sh`](budget/budget-kill-deploy.sh) | Emergency : tear down all GCP / OVH resources if budget breached. | Manual / paged |

## `cluster/` — Cluster lifecycle

Bring clusters up / down on demand to control cost (per [ADR-0022](../docs/adr/0022-ephemeral-demo-cluster.md)).

| Script | Purpose |
|---|---|
| [`cluster-status.sh`](cluster/cluster-status.sh) | One-glance status across all configured clusters (GKE + OVH + kind). |
| [`demo/`](cluster/demo/) | Demo cluster bring up + tear down (GKE Autopilot). |
| [`ovh/`](cluster/ovh/) | OVH managed-k8s cluster lifecycle. |
| [`test-all.sh`](cluster/test-all.sh) | Smoke test : kubectl get nodes + actuator/health on every configured cluster. |

## `dev/` — Local dev workflow

Day-to-day developer aid. All scripts have `--help` / dry-run modes.

| Script | Purpose | Wired to |
|---|---|---|
| [`stability-check.sh`](dev/stability-check.sh) | Multi-section preflight before tagging stable-vX.Y.Z (lint + test + build + sec-scan). | Manual / cron |
| [`runner-healthcheck.sh`](dev/runner-healthcheck.sh) | Verify Docker `gitlab-runner` container is up + group runner is online from GitLab. Auto-restart on failure. | launchd every 5 min |
| [`burn-slo-budget.sh`](dev/burn-slo-budget.sh) | Controlled SLO budget burn for live demo (chaos requests + Grafana annotations). | Manual / demo |

## `launchd/` — macOS launchd plists

Cron-equivalent on macOS. Install with `launchctl load -w ~/Library/LaunchAgents/<plist>`.

| Plist | Wraps | Schedule |
|---|---|---|
| [`com.mirador.ovh-budget.plist`](launchd/com.mirador.ovh-budget.plist) | `bin/budget/ovh-alert.sh` | Daily 09:00 |
| [`com.mirador.runner-healthcheck.plist`](launchd/com.mirador.runner-healthcheck.plist) | `bin/dev/runner-healthcheck.sh` | Every 5 min |

## `ship/` — Release engineering

Release + governance automation.

| Script | Purpose | Wired to |
|---|---|---|
| [`changelog.sh`](ship/changelog.sh) | Generate CHANGELOG.md entry from commits since last `stable-v*` tag (Conventional Commits). | Manual pre-tag |
| [`gitlab-release.sh`](ship/gitlab-release.sh) | Create GitLab Release object linked to a tag, with rendered changelog body. | Manual post-tag |
| [`check-default-branch.sh`](ship/check-default-branch.sh) | Verifies all 4 mirador1 projects have `default_branch=main` (after the 2026-04-25 incident). | Manual / pre-tag |
| [`renovate-sync.sh`](ship/renovate-sync.sh) | Sync `renovate.json` across 4 repos from `renovate-base.json` (per [ADR-0059](../docs/adr/0059-renovate-base-preset.md)). | Manual after editing renovate-base.json |

## Conventions

- **Shebang** : `#!/usr/bin/env bash`.
- **Strict mode** : `set -euo pipefail` (or `set -uo` if intentional fall-through).
- **Header comment** : every script starts with a block explaining WHY it
  exists, USAGE, and FAILURE MODES (3-line minimum).
- **Color helpers** : `G='\033[32m' R='\033[31m' Y='\033[33m' N='\033[0m'`
  + `ok() { printf "${G}✓${N} %s\n" "$1"; }` etc.
- **Dry-run mode** : every destructive script accepts `--dry-run`.
- **Exit codes** : 0 = OK, 1 = expected failure (alertable), 2 = misuse.

## Adding a new script

1. Pick the right group (or propose a new one in this README).
2. Use the header template — copy from any existing script.
3. Update this README with a row in the matching table.
4. If it should be cron'd, add a `bin/launchd/` plist + document in the
   plist comment + this README.
5. If it has a per-cluster / per-provider variant, mirror the existing
   structure (e.g. `bin/cluster/{gcp,ovh}/` not `bin/cluster-gcp.sh`).

## See also

- [`docs/adr/`](../docs/adr/) — cross-cutting architectural decisions
- [`docs/PRODUCTION-READINESS.md`](../docs/PRODUCTION-READINESS.md) — checklist
- [`docs/demo/live-demo.md`](../docs/demo/live-demo.md) — interview playbook
