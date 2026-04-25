# ADR-0055 — Shell-based release automation (no semantic-release)

- **Status**: Accepted
- **Date**: 2026-04-23
- **Deciders**: Mirador maintainers
- **Supersedes**: release-please configuration (removed 2026-04-23 —
  previously scaffolded but never activated, see deleted
  `config/release-please-config.json` + `.release-please-manifest.json`)
- **Related**:
  [ADR-0050](0050-ci-yaml-modularisation-plan.md) (CI modularisation),
  [CLAUDE.md → "Tag every green stability checkpoint"](../../CLAUDE.md)

## Context

Mirador used two parallel release patterns :

1. **`stable-vX.Y.Z` tags** — human-driven stability checkpoints
   created per the global CLAUDE.md rule "tag every green stability
   checkpoint, never tag on red". These have always been the source
   of truth for "is this commit safe to roll back to?".
2. **`vX.Y.Z` tags** (release-please) — were planned via
   `googleapis/release-please` configured in `.gitlab-ci.yml` on both
   repos. Never activated because the tool is **GitHub-API-only** :
   even with `--token <GitLab PAT> --repo-url https://gitlab.com/...`,
   release-please still hits `api.github.com/graphql` for its
   "existing releases" query and 401s. Evidence :
   [svc pipeline #660 release-please job](https://gitlab.com/mirador1/mirador-service/-/pipelines/2472861553).

The release-please job was `when: never`-gated 2026-04-22 to stop
red-firing every main merge, pending a tool swap decision.

Three candidates were evaluated :

| Tool | Setup | Deps added | CI cost | Native GitLab? |
|---|---|---|---|---|
| `semantic-release` + `@semantic-release/gitlab` | 1-2 h | `node_modules` on a Java repo | ~2 min/tag | ✅ full |
| `standard-version` | 30 min | `node_modules` on a Java repo | 0 (local) | ⚠️ partial |
| Hand-rolled bash (`bin/ship/changelog.sh`) | 1 h | None | 0 | ✅ full |

The second driver is **release cadence**. Mirador is a solo-maintainer
portfolio project with ~3-6 `stable-v*` tags per dev day. At that
rate, a CI job on tag push would burn 15-30 min × 4-5 tags/day of
free-runner quota for work the MR pipeline already validated. The
tag is just a named pointer to a commit ; tagging does not introduce
any new risk that warrants re-running the entire security + build
+ deploy pipeline.

The third driver is **supply-chain footprint**. Adding
`semantic-release` pulls in 120+ transitive npm packages on a repo
whose primary language is **Java** (Spring Boot 4). Every dep is an
audit surface that Renovate will eventually ask us to bump.

## Decision

Ship **two local shell scripts** under
[`bin/ship/`](../../bin/ship/) as the release automation :

- **[`bin/ship/changelog.sh`](../../bin/ship/changelog.sh)** (~160 LOC
  bash) — reads `git log <last-stable-v*>..HEAD` output, classifies
  each subject by Conventional-Commit type
  (`feat!` / `feat` / `fix` / `perf` / `refactor` / `docs` / `test` /
  `chore` / `ci` / `build` / `style`), groups into emoji sections
  (💥 Breaking, ✨ Features, 🐛 Bug fixes, ⚡ Performance, ♻️ Refactoring,
  📚 Documentation, 🧪 Tests, 🔧 Chore, 👷 CI, 📦 Build, 💄 Style),
  prepends the new entry to `CHANGELOG.md`. Flags : `--since <ref>`,
  `--dry-run`, `--include-chore`.

- **[`bin/ship/gitlab-release.sh`](../../bin/ship/gitlab-release.sh)**
  (~80 LOC bash) — takes a `stable-v*` tag, runs `glab release
  create` with the annotated tag message (or custom `--notes`) to
  create a GitLab Release object at `/-/releases`.

The workflow (documented in
[`docs/how-to/changelog-workflow.md`](../how-to/changelog-workflow.md))
is 5 steps :

```bash
bin/ship/changelog.sh                                # 1. regen entry
git add CHANGELOG.md && git commit -m "chore(changelog): bump for vX.Y.Z"
git tag -a stable-vX.Y.Z -m "..."                    # 2. tag
git push origin stable-vX.Y.Z                        # 3. push
bin/ship/gitlab-release.sh stable-vX.Y.Z             # 4. promote
                                                     # 5. announce (optional)
```

Both repos (svc + UI) ship identical copies of the scripts
(confirmed in `gitlab-release.sh`'s inline doc). Symmetric cleanup
deleted release-please from both repos 2026-04-23 in svc
[MR !169](https://gitlab.com/mirador1/mirador-service/-/merge_requests/169)
+ UI [MR !102](https://gitlab.com/mirador1/mirador-ui/-/merge_requests/102).

## Consequences

### Positive

- **Zero new `node_modules/`** on a Java repo. `package.json` on
  the svc side stays Angular-UI-only ; no JS supply-chain drift.
- **Zero CI runner burn**. A `stable-v*` tag push does not trigger
  any pipeline because `.gitlab-ci.yml`'s workflow:rules don't
  include tag refs. The scripts execute locally in ~1 s each.
- **~200 LOC readable in one pass**. New contributors can read both
  scripts end-to-end in < 10 min. `semantic-release` would require
  learning its plugin model + config schema (~45 min reading).
- **Single tag family**. `stable-vX.Y.Z` is the only release tag ;
  the parallel `vX.Y.Z` scheme release-please would have introduced
  is gone. Reviewers at
  <https://gitlab.com/mirador1/mirador-service/-/tags> see one line,
  not two.
- **Renovate-free**. No new dependency for Renovate to monitor.

### Negative

- **Manual trigger**. Releases don't happen automatically on main
  merge — the maintainer must run the 5-step workflow consciously.
  Acceptable at current solo + ~3-6 tags/day cadence ; not scalable
  past 2-3 contributors.
- **No automatic semver bump**. The scripts don't pick `vX.Y.Z` for
  you ; you decide based on the Conventional-Commit types present.
  Small cognitive overhead that `semantic-release` would remove.
- **CHANGELOG regeneration is stateless**. Unlike release-please
  which maintains a manifest of "last released SHA", `changelog.sh`
  re-reads git log each time. If the last tag is deleted or
  rewritten, the next entry could overlap with a previous one.
  Mitigated by : tags are annotated + signed + protected from delete
  on GitLab main ; explicit `--since <ref>` flag overrides.
- **No cross-repo coordination**. When svc and UI need a
  coordinated release (e.g. API contract change), the maintainer
  runs the workflow twice. Semantic-release wouldn't solve this
  either without a monorepo tool (Lerna / Turborepo), so it's a
  wash.

### Neutral

- **GitHub mirror unaffected**. The mirror still receives tag
  pushes via `bin/ship/ship.sh --wait` (ADR-0028). GitHub Releases
  are not auto-populated — per ADR-0028, the mirror is read-only
  for tags.
- **Conventional Commits enforcement unchanged**. `lefthook.yml`
  commit-msg hook still requires the format ; the scripts just
  *consume* it instead of a Node tool.

## Alternatives considered

### Alternative A — `semantic-release` + `@semantic-release/gitlab`

Industry-standard, GitLab-native (uses GitLab API for everything),
automatic semver bumping, automatic release notes, automatic
CHANGELOG, plugin ecosystem. **Pro** : fully automated, battle-
tested, what most teams use. **Con** : 120+ npm packages added as
a build-time dep on a Java project, 2 min/tag CI time × 3-6 tags/
day = 6-12 min/day of free-runner quota burned for work the MR
pipeline already validated, plugin learning curve. **Revisit when :**
team grows past 2-3 contributors AND tag cadence stabilises < 1/day.
At that point file a new ADR superseding this one.

### Alternative B — `standard-version`

Lighter than `semantic-release`, runs locally (no CI job needed).
**Pro** : closest alternative to the hand-rolled version, plugin-free.
**Con** : still adds `node_modules` on a Java repo ; last release
was 2022 (effectively unmaintained) ; npm now recommends
`commit-and-tag-version` which is a hard fork. Not worth the
dependency for ~50 LOC of bash we can write ourselves.

### Alternative C — Keep release-please disabled, hand-edit CHANGELOG.md

Status quo before this ADR. **Pro** : zero tooling. **Con** :
every stable-v tag required hand-writing the markdown — error-prone,
inconsistent categorisation, forgets to link commit SHAs, repetitive.
Inferior to option D for ~1 h of script-writing.

### Alternative D — `bin/ship/` shell scripts (CHOSEN)

See "Decision" section above. Fits the solo-maintainer cadence
+ zero-dep goal + CI-quota-aware posture.

### Alternative E — Use `git-cliff`

Rust-based CHANGELOG generator, similar to `standard-version` but
standalone binary (no `node_modules`). **Pro** : zero npm deps,
well-maintained, fast. **Con** : adds a Rust binary install
(brew tap / cargo / curl install) to every contributor's machine ;
config is TOML that rivals `release-please-config.json` in surface
area ; learning curve for categorisation templating. If the hand-
rolled bash ever outgrows its current scope, `git-cliff` is the
obvious next step — but not needed today. Explicitly noted as
"revisit if the bash ever crosses ~300 LOC".

## Revisit criteria

This ADR **must** be re-evaluated when any of :

1. **Team grows past 2 contributors** — manual release workflow
   stops scaling when multiple people might want to ship tags
   independently ; automation becomes worth the dependency cost.
2. **Tag cadence drops below 1/day** — CI-per-tag cost becomes
   negligible ; `semantic-release` becomes worth considering.
3. **Cross-repo release coordination becomes load-bearing** —
   e.g. svc + UI need lock-step releases because of versioned APIs.
   Monorepo tooling (Lerna / Turborepo) would shape the decision.
4. **Hand-rolled `changelog.sh` crosses ~300 LOC** — complexity
   threshold where `git-cliff` or `semantic-release` become the
   simpler option.

Until one of those triggers, the shell scripts are canon.

## References

- [`bin/ship/changelog.sh`](../../bin/ship/changelog.sh) — the generator
- [`bin/ship/gitlab-release.sh`](../../bin/ship/gitlab-release.sh) — the promoter
- [`docs/how-to/changelog-workflow.md`](../how-to/changelog-workflow.md) — 5-step workflow
- [svc MR !169](https://gitlab.com/mirador1/mirador-service/-/merge_requests/169) — svc release-please removal
- [UI MR !102](https://gitlab.com/mirador1/mirador-ui/-/merge_requests/102) — UI release-please removal
- [release-please upstream issue about GitLab support](https://github.com/googleapis/release-please/issues/1024)
  — confirms GitHub-only
- [semantic-release GitLab plugin](https://github.com/semantic-release/gitlab)
- [git-cliff](https://git-cliff.org/)
