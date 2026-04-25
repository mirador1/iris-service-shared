# mirador-shared

Shared infrastructure + tooling for the Mirador project family. **Submoduled
into `mirador-service` (Java) + `mirador-service-python`** under
`infra/shared/`. Scripts reference submodule paths from the parent repos.

## What lives here

| Path | Purpose | Consumer |
|---|---|---|
| `compose/dev-stack.yml` | Postgres + Redis + Kafka + LGTM (identical for both backends) | svc + python `bin/demo-up.sh` |
| `bin/budget/` | GCP + OVH budget alert scripts | svc + python (cron via launchd) |
| `bin/cluster/ovh/` | OVH managed-k8s cluster up/down/init scripts | svc + python on-demand |
| `bin/launchd/` | macOS launchd plists (budget cron, etc.) | local dev workstations |
| `ci-templates/` | GitLab CI YAML templates (`include:` from consumer repos) | all 3 mirador repos |
| `infra/observability/` | OTel Collector override config | svc primary, python optional |
| `docs/adr/` | Cross-cutting ADRs (decisions that span ≥ 2 repos) | reference |

## Why a separate repo (and not merged into one of the others)

Per cross-cutting [ADR-0001](docs/adr/0001-shared-repo-via-submodule.md) :
shared content is genuinely 80%+ identical between Java + Python — extracting
removes drift risk + lets us bump postgres/kafka/redis versions in one place.
Submodule (vs polyrepo include or copy-paste) chosen because it pins a
specific SHA in each consumer (no breakage cascade) AND keeps the consumer
repos' visual structure clean (one folder = one boundary).

## How to update

```bash
# In mirador-shared :
$ cd /Users/benoitbesson/dev/workspace-modern/mirador-shared
$ git switch dev
# … edit, commit, push …
$ git push origin dev
# Optionally tag if it's a stable checkpoint :
$ git tag stable-v0.1.0 && git push origin stable-v0.1.0

# In the consumer repo (svc OR python) :
$ cd ../mirador-service          # or ../mirador-service-python
$ cd infra/shared
$ git pull origin dev            # or git checkout stable-v0.1.0 for tag
$ cd ../..
$ git add infra/shared
$ git commit -m "chore: bump shared submodule to <sha>"
$ git push
```

## How to clone (consumer side, first time)

The submodule pointer doesn't auto-populate. After cloning the parent :

```bash
git clone https://gitlab.com/mirador1/mirador-service.git
cd mirador-service
git submodule update --init --recursive
# OR : git clone --recurse-submodules <parent-url>   # both at once
```

## License

MIT
