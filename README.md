# mirador-service-shared

[![BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue)](LICENSE)
![Sloth SLO](https://img.shields.io/badge/Sloth-SLO_rules-2D7FF9)
![Grafana LGTM](https://img.shields.io/badge/Grafana-LGTM_dashboards-F46800?logo=grafana&logoColor=white)
![Argo CD](https://img.shields.io/badge/Argo_CD-GitOps-EF7B4D?logo=argo&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-GCP_+_OVH-844FBA?logo=terraform&logoColor=white)
![Kustomize](https://img.shields.io/badge/Kustomize-overlays-326CE5?logo=kubernetes&logoColor=white)

Shared **infrastructure + observability + CI templates + cross-cutting docs**
for the [mirador1](https://gitlab.com/mirador1) project family. Submoduled
into `mirador-service-java` and `mirador-service-python` under `infra/shared/`.

## What this proves

- **Polyrepo coherence without monorepo lock-in** : 4 sibling repos share
  this submodule for the 80% of infra that's truly identical (compose stack,
  K8s manifests, OTel config, CI templates, cross-cutting ADRs, SLO rules,
  Grafana dashboards). Submodule pin = no cascade breakage when shared moves.
- **Operational hygiene scripts** : default-branch verification, runner
  healthcheck cron, GCP + OVH budget alerts, release automation, stability
  checks. Each script has a `--dry-run` mode + a launchd plist when
  applicable.
- **Cross-cutting Grafana dashboards** : SLO Overview (spans Java + Python
  via Sloth's universal `slo:current_burn_rate:ratio` metric). Repo-specific
  dashboards (latency heatmap, Apdex, breakdown by endpoint) live IN their
  own repos at `<repo>/infra/observability/grafana-dashboards/` because
  they query repo-specific metric names (Java's
  `http_server_requests_seconds_*` vs Python's `starlette_*`).
- **PrometheusRules** : generated per-repo via Sloth + each repo's
  `wrap-as-prometheusrule.py`, output to that repo's
  `deploy/kubernetes/observability-prom/mirador{-py}-slo.yaml`. The
  cross-cutting `mirador-alerts.yaml` (backend-down, kafka lag) stays here
  in shared.
- **Renovate base preset** : 4 repos share common config (auto-merge patch,
  Docker pinDigests, codeowners assignee) ; repo-specific groups (Spring Boot,
  FastAPI, Angular) preserved by `bin/ship/renovate-sync.sh`.

## What lives here

| Path | Purpose | Consumer |
|---|---|---|
| `compose/dev-stack.yml` | Postgres + Redis + Kafka + LGTM + Ollama | java + python `bin/demo-up.sh` |
| `bin/budget/` | GCP + OVH budget alert scripts | java + python (cron via launchd) |
| `bin/cluster/ovh/` | OVH managed-k8s cluster up/down/init scripts | java + python on-demand |
| `bin/dev/` | Healthchecks + chaos burn-SLO-budget script | local dev + cron |
| `bin/ship/` | Release automation + default-branch + renovate-sync | manual / CI |
| `bin/launchd/` | macOS launchd plists (budget cron, runner healthcheck) | local dev workstations |
| `ci-templates/` | GitLab CI YAML templates (`include:` from consumers) | all 3 service repos |
| `infra/observability/grafana/dashboards-lgtm/` | Cross-cutting Grafana dashboards (SLO Overview spans both services + demo + service-control + logs) | LGTM provisioning |
| `infra/observability/` | OTel Collector + Prometheus shared config | java + python |
| `deploy/kubernetes/` | Cross-cutting K8s manifests (Argo CD apps, ESO, Argo Rollouts, network policies, observability stack) | clusters |
| `deploy/kubernetes/observability-prom/mirador-alerts.yaml` | Cross-cutting alert rules (backend down, kafka lag, etc.) | kube-prometheus-stack operator |
| `deploy/terraform/{gcp,ovh}/` | Cluster lifecycle | manual / CI |
| `docs/adr/` | 9 cross-cutting ADRs (decisions ≥ 2 repos) | reference |
| `docs/slo/review-cadence.md` | Monthly + quarterly + post-incident SLO review framework | SRE team |
| `renovate-base.json` | Common Renovate config | synced into 4 repos via `bin/ship/renovate-sync.sh` |

## Why a separate repo (and not merged into one of the others)

Per cross-cutting [ADR-0001](docs/adr/0001-shared-repo-via-submodule.md) :
shared content is genuinely 80%+ identical between Java + Python — extracting
removes drift risk + lets us bump postgres/kafka/redis versions in one place.
Submodule (vs polyrepo include or copy-paste) chosen because it pins a
specific SHA in each consumer (no breakage cascade) AND keeps the consumer
repos' visual structure clean (one folder = one boundary).

## How to update

```bash
# In mirador-service-shared :
$ cd /Users/benoitbesson/dev/workspace-modern/mirador-service-shared
$ git switch main
# … edit, commit, push …
$ git push origin main

# In the consumer repo (java OR python) :
$ cd ../mirador-service-java     # or ../mirador-service-python
$ cd infra/shared
$ git pull origin main
$ cd ../..
$ git add infra/shared
$ git commit -m "chore(shared): bump SHA — <reason>"
$ git push
```

The consumer repo's CI re-runs against the new shared SHA — that's the
verification step. Tag stable-vX.Y.Z when a milestone lands.

## How to clone (consumer side, first time)

The submodule pointer doesn't auto-populate. After cloning the parent :

```bash
git clone https://gitlab.com/mirador1/mirador-service-java.git
cd mirador-service-java
git submodule update --init --recursive
# OR : git clone --recurse-submodules <parent-url>   # both at once
```

## See also

- [CHANGELOG](CHANGELOG.md) — release notes per checkpoint
- [CONTRIBUTING](CONTRIBUTING.md) — workflow + multi-repo blast radius warning
- [SECURITY](SECURITY.md) — vulnerability disclosure
- [ADR-0001 — Shared repo via submodule](docs/adr/0001-shared-repo-via-submodule.md)
- [ADR-0058 — SLO/SLA via Sloth](docs/adr/0058-slo-sla-with-sloth.md)
- [SLO review cadence](docs/slo/review-cadence.md)
- Sibling repos : [java](https://gitlab.com/mirador1/mirador-service-java) · [python](https://gitlab.com/mirador1/mirador-service-python) · [ui](https://gitlab.com/mirador1/mirador-ui)

## License

[BSD-3-Clause](LICENSE)
