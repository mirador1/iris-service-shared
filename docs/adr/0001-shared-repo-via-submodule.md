# ADR-0001 : Shared infra extraction via git submodule

**Status** : Accepted
**Date** : 2026-04-25
**Related repos** : `mirador-service`, `mirador-service-python`, `mirador-ui`

## Context

After 4 waves of Python work, the duplication between `mirador-service` (Java)
and `mirador-service-python` had grown to a tangible cost :
- `docker-compose.yml` dev stack (postgres + redis + kafka + LGTM) 80 % identical
- `bin/budget/{budget,ovh-alert,gcp-cost-audit,ovh-cost-audit}.sh` 100 % identical
- `bin/cluster/ovh/{up,down,init-backend}.sh` 100 % identical
- `bin/launchd/com.mirador.ovh-budget.plist` 100 % identical
- CI templates (conventional-commits, docker multi-arch, sonar-scanner image
  build) drifting between repos

User asked : "should there be a separate repo to share what's both in Java
and Python (like infrastructure) ? Is having an infra repo a thing ?"

Three options considered :
- **(a)** Status quo + ADR documenting the duplication as intentional
- **(b)** GitLab CI templates project (lightweight, CI-only sharing)
- **(c)** Full `mirador-infra` repo (k8s + CI + scripts + everything)
- **(d)** Submodule of a focused `mirador-service-shared` repo (dev-stack + budget + CI templates)

## Decision

**Option (d) — `mirador-service-shared` repo + submodule into svc + python.**

Rationale (per user 2026-04-25) :
> "Dès que Java et Python pourraient partager plus que la fais intégration,
> continue, je pense que le choix du Submodule est pertinent. D'autant plus
> qu'il permet visuellement de ne pas impacter la vision d'un seul."

1. **More than just integration tests is genuinely shared** (dev-stack +
   budget + OVH cluster scripts + CI templates) — duplication cost will
   keep growing as more languages join (eventual Go/Rust/etc. service).
2. **Submodule SHA-pin** : each consumer freezes a specific shared-repo SHA.
   Bumping the shared repo doesn't break consumers until they explicitly
   re-pull. No breakage cascade.
3. **Visual non-intrusion** : the submodule appears as one folder
   (`infra/shared/`) in each consumer — a clear boundary. Vendoring code
   doesn't pollute the consumer's structure or git history.

## Repo structure

```
mirador-service-shared/
├── compose/dev-stack.yml         # postgres + redis + kafka + LGTM
├── bin/
│   ├── budget/                   # GCP + OVH alert + cost audit
│   ├── cluster/ovh/              # cluster up/down/init-backend
│   └── launchd/                  # macOS cron plists
├── ci-templates/                 # GitLab CI YAML templates
│   ├── conventional-commits.yml
│   ├── docker-multiarch.yml
│   └── …
├── infra/observability/          # OTel Collector override
└── docs/adr/                     # cross-cutting ADRs (this file)
```

Submoduled into consumers at :
- `mirador-service/infra/shared/`
- `mirador-service-python/infra/shared/`

UI repo NOT submoduled for now (no shared content yet beyond the conventional-commits hook — adding submodule for one CI template is overkill ; will revisit if more shared content emerges).

## Consequences

### Positive
- **Single source of truth** for the dev-stack docker-compose. Bump postgres
  16.6 → 17.0 once, both services see it.
- **No drift** for budget alert scripts (which we want bug-for-bug identical).
- **Cross-cutting ADRs** (like this one) live in one place + are linked from
  consumers.
- **Easier polyglot extension** : adding a 3rd backend (Go/Rust/...) inherits
  the dev-stack + scripts for free.

### Negative
- **Submodule UX friction** : new contributors MUST run
  `git submodule update --init --recursive` after clone. Documented in each
  consumer's README + CLAUDE.md.
- **Two-commit bump workflow** : update shared → tag/push there → bump SHA in
  consumer → commit/push consumer. Mitigated by the SHA-pin guarantee
  (no auto-cascade breakage).
- **CI must enable submodules** : `GIT_SUBMODULE_STRATEGY=recursive` in
  `.gitlab-ci.yml` of each consumer.
- **Kubernetes manifests NOT extracted** (yet) : Java + Python images differ,
  so the manifests have legitimate per-repo specifics. Re-consider after
  more usage.

### Neutral
- **Versioning** : we'll tag stable-vX.Y.Z on shared repo when content
  stabilizes, and consumers can pin to those tags via `git submodule
  set-url + git -C infra/shared checkout <tag>`. Not all submodule bumps
  need to be on tagged versions ; SHA-pinning is enough for ad-hoc bumps.

## Alternatives considered

### (a) Status quo + ADR explicite
**Pro** : zero refactor cost, preserves "polyrepo by design" pedagogical
clarity.
**Con** : duplication cost compounds as content grows. Already 4+ shared
files identical between Java + Python.

### (b) GitLab CI templates project (CI-only)
**Pro** : 5-min setup, native GitLab feature, no submodule complexity.
**Con** : restricted to `.yml` files — can't share docker-compose or
shell scripts. Solves the smallest part of the problem.

### (c) Full `mirador-infra` repo (everything)
**Pro** : maximum DRY.
**Con** : k8s manifests / Dockerfiles legitimately differ between Java +
Python. Forcing them into one repo creates parametric complexity worse than
the duplication it removes.

### (d) Submodule of focused `mirador-service-shared` ← chosen
**Pro** : SHA-pin safety, visual non-intrusion, scales incrementally
(start with dev-stack + budget, grow as needed).
**Con** : submodule UX friction (acceptable + documented).

## Migration plan

1. Create `mirador1/mirador-service-shared` GitLab project (DONE).
2. Copy shared content from svc + python into `mirador-service-shared/` (DONE).
3. Add submodule `infra/shared/` in svc + python.
4. Update `bin/run.sh` + `bin/demo-up.sh` in each consumer to reference
   `infra/shared/compose/dev-stack.yml` instead of local `docker-compose.yml`.
5. (Optional, later) Move `bin/budget/` etc. fully out of svc, leaving a
   thin wrapper that delegates to `infra/shared/bin/budget/*`.
6. Tag `mirador-service-shared` stable-v0.1.0 once everything builds end-to-end.

## See also

- [GitLab submodule docs](https://docs.gitlab.com/ee/ci/git_submodules.html)
- [GitLab CI include with project](https://docs.gitlab.com/ee/ci/yaml/includes.html#include-files-from-another-project)
- This repo's [README](../../README.md) — ops cheat-sheet
