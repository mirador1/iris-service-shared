# Contributing to mirador-service-shared

`mirador-service-shared` is the **infrastructure / observability / CI
templates / cross-cutting docs** repo for the [mirador1](https://gitlab.com/mirador1)
project family. It's submoduled into the consuming service repos under
`infra/shared/`.

Changes here have **multi-repo blast radius** : a bad K8s manifest or
broken CI template breaks all 4 sibling repos. Review accordingly.

## Where to contribute

GitLab is canonical : [gitlab.com/mirador1/mirador-service-shared](https://gitlab.com/mirador1/mirador-service-shared).

## What lives here

| Path | Purpose |
|---|---|
| `compose/dev-stack.yml` | Postgres + Redis + Kafka + LGTM dev stack |
| `bin/{ship,dev,cluster,budget,launchd}/` | Operational scripts |
| `ci-templates/*.yml` | GitLab CI YAML templates `include`d from consumer repos |
| `infra/observability/` | OTel Collector + Grafana provisioning + Sloth-generated SLO rules |
| `deploy/kubernetes/` | K8s manifests (Argo CD apps, ESO, observability stack) |
| `deploy/terraform/{gcp,ovh}/` | Cluster lifecycle Terraform |
| `docs/adr/` | Cross-cutting ADRs (decisions affecting ≥ 2 repos) |
| `renovate-base.json` | Common renovate config (synced into 4 repos via `bin/ship/renovate-sync.sh`) |

## Update workflow

```bash
# In mirador-service-shared :
git switch main
# … edit, commit, push …
git push origin main
# Optionally tag if it's a stable checkpoint :
git tag stable-v0.X.Y && git push origin stable-v0.X.Y

# In each consumer repo (svc-java + python) :
cd ../mirador-service-java/infra/shared  # or ../mirador-service-python/infra/shared
git pull origin main
cd ../..
git add infra/shared
git commit -m "chore(shared): bump SHA — <reason>"
git push origin dev
```

The consumer repo's CI re-runs against the new shared SHA — that's the
verification step.

## Renovate sync

When editing `renovate-base.json`, run :

```bash
./bin/ship/renovate-sync.sh
```

This regenerates each consuming repo's `renovate.json` (preserves their
repo-specific `groupName` rules + gitlabci block + top-level description ;
overwrites the common config).

## SLO rules generation

When editing SLO definitions (in the consuming service repos, e.g.
`mirador-service-java/docs/slo/slo.yaml`), regenerate the PrometheusRule :

```bash
cd ../mirador-service-java
sloth generate -i docs/slo/slo.yaml -o /tmp/mirador-slo-rules.yaml
python3 docs/slo/wrap-as-prometheusrule.py
# Output : ../mirador-service-shared/deploy/kubernetes/observability-prom/mirador-slo.yaml

cd ../mirador-service-shared
git add deploy/kubernetes/observability-prom/mirador-slo.yaml
git commit -m "chore(slo): regenerate Java rules from updated slo.yaml"
git push
```

Same for Python (`mirador-py-slo.yaml`).

## Tests / validation

The shared repo has no unit tests — it's config / templates / docs.
Validation happens at consumer-repo CI level :
- The consuming repo's pipeline runs against the bumped submodule SHA.
- If the bump breaks anything, the consumer's CI is red ; fix in shared,
  bump again.

## See also

- [Java sibling CONTRIBUTING.md](https://gitlab.com/mirador1/mirador-service-java/-/blob/main/CONTRIBUTING.md)
- [Python sibling CONTRIBUTING.md](https://gitlab.com/mirador1/mirador-service-python/-/blob/main/CONTRIBUTING.md)
- [ADR-0001 — Shared repo via submodule](docs/adr/0001-shared-repo-via-submodule.md)
- [SLO review cadence](docs/slo/review-cadence.md)
