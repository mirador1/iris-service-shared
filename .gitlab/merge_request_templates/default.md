<!-- Thanks for the MR. Answer what's relevant; delete what isn't. -->

## What

<!-- One sentence: what does this change? -->

## Why

<!-- The reason — usually the linked issue's problem, or a paragraph here if none. -->

## ADRs

<!-- If this change makes or supersedes an architectural decision, link the ADR. -->

- [ ] New ADR added under `docs/adr/`
- [ ] N/A — not an architectural change

## Checks

- [ ] `bin/dev/runner-healthcheck.sh` + `bin/ship/check-default-branch.sh` green
- [ ] CI pipeline green (or skip with rationale for flaky jobs)
- [ ] Docs updated (README / runbook / technologies.md / methods-and-techniques.md)
- [ ] If CI added a new `$VAR`, it's documented in cross-cutting ADR
- [ ] If README touched, FR version updated too (or `LEFTHOOK=0` rationale)

## Screenshots / traces

<!-- For UI changes, before/after. For backend behaviour changes, Tempo trace URL. -->

Closes #
