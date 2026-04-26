# ADR-0059 : Renovate base preset + sync script (option B)

**Status** : Accepted
**Date** : 2026-04-26
**Cross-cutting** : applies to all 4 mirador1 repos (java + ui + python + shared).
**Sibling files** : `renovate-base.json` + `bin/ship/renovate-sync.sh`.

## Context

Each of the 4 mirador1 repos started with its own hand-maintained
`renovate.json`. Drift accumulated quickly :
- Java had `assigneesFromCodeOwners: true` ; Python didn't.
- UI had a different `prHourlyLimit` than the others.
- The "auto-merge patch + minor + digest" rule was repeated in each repo
  with slightly different wording.
- A sec config tweak meant editing 4 files in lockstep — easy to miss one.

Two consolidation patterns considered :

### Option A — Renovate hosted preset

Publish `renovate.json` as a Renovate preset (e.g.
`gitlab>mirador1/mirador-service-shared:renovate.json`) and have each
repo's `renovate.json` simply `extends` the preset URL.

Pros :
- Industry-standard Renovate pattern.
- Bumps in shared instantly visible to all consumers (no sync step).

Cons :
- Renovate's preset resolver requires the file to be at a specific path
  (typically `default.json` in a public repo).
- Adds a network dependency at every Renovate run (GitLab fetch).
- Hard to template repo-specific bits (e.g. Java's Maven groups vs Python's
  pip groups) — would need multiple files OR conditional rules in one preset.
- Less visible to a repo reader : opening `renovate.json` shows extension URL
  only ; you have to navigate to the preset to understand the actual config.

### Option B — Local base file + sync script

Maintain `renovate-base.json` in shared. Provide
`bin/ship/renovate-sync.sh` that merges the base into each repo's
`renovate.json`, preserving repo-specific `groupName` rules + `gitlabci`
block + top-level `description`.

Pros :
- Each repo's `renovate.json` is self-contained + readable in-place.
- Repo-specific rules stay alongside the common ones (no indirection).
- No network dependency at Renovate evaluation time.
- Easy to template per-repo (the script is jq, can do anything).

Cons :
- Sync step required when base changes (manual `bin/ship/renovate-sync.sh`).
- Risk of forgetting to re-sync — mitigated by `--check` mode that
  diffs and exits 1 on drift (can be wired into CI as a check).

## Decision

**Option B** — local base file + sync script.

Rationale : each repo's `renovate.json` should remain a complete, readable
artifact in its own right ; indirection via Renovate hosted preset trades
visibility for instant propagation, which doesn't matter at our 4-repo scale.

Workflow :

1. **Edit** `mirador-service-shared/renovate-base.json` — common config that
   all 4 repos share.
2. **Run** `bin/ship/renovate-sync.sh` — regenerates each consuming repo's
   `renovate.json` (preserves repo-specific `groupName` rules + `gitlabci`
   block + top-level `description`).
3. **Review** the diff per repo (`git diff renovate.json` in each).
4. **Commit + push** in each repo (4 commits, 4 pushes, no link between
   them — each repo's `renovate.json` is self-contained).

Drift detection : `bin/ship/renovate-sync.sh --check` exits 1 if any repo
drifts from the expected output. Wire into a future CI job that blocks
merges if `renovate.json` was hand-edited without re-syncing the base.

## Consequences

**Pros** :
- 1 source of truth for common rules (extends, schedule, automerge
  policy, vulnerability alerts, lockFileMaintenance).
- Repo-specific groups (Java's Spring Boot, Python's FastAPI, UI's
  Angular, Shared's K8s tools) live with their repos.
- No Renovate-hosted-preset dependency — works fully offline.
- The `bin/ship/renovate-sync.sh --check` mode catches drift in CI.
- New project added to mirador1 ? Add it to the script's `REPO_PATHS`
  array, run sync, commit. ~5 minutes.

**Cons** :
- Manual sync step. Forgotten = drift = MR's renovate.json shows extra
  hand-edits during review. Mitigated by the `--check` mode + an
  eventual CI job.
- The script uses `jq` and bash — adds a dependency on a Unix shell.
  Acceptable since Renovate itself runs in CI on Linux.

**Neutral** :
- Generated `renovate.json` files are larger (~150 lines each) than a
  hosted-preset `extends` (would be ~3 lines). Acceptable tradeoff for
  in-place readability.

## Validation

- 4 repos synced 2026-04-26 : java + ui + python + shared all show
  `bin/ship/renovate-sync.sh --check` as green.
- Common rules count per repo : 4 (auto-merge patch+pin+digest, minor for
  build/dev/plugin deps, Docker pinDigests, SNAPSHOT block).
- Repo-specific rules preserved : Java has Spring Boot + Micrometer/OTel +
  Testcontainers + Maven plugins ; Python has FastAPI / Pydantic stack +
  SQLAlchemy/asyncpg/Alembic + OTel + Lint+type tooling + pytest ;
  UI has Angular family ; Shared has K8s tools (Argo / ESO / Chaos Mesh /
  LGTM / Kyverno / cert-manager).

## See also

- [`renovate-base.json`](../../renovate-base.json) — the source of truth.
- [`bin/ship/renovate-sync.sh`](../../bin/ship/renovate-sync.sh) — the merge script.
- ADR-0001 — Shared repo via submodule (overall pattern).
- [Renovate preset documentation](https://docs.renovatebot.com/config-presets/) — option A reference.
