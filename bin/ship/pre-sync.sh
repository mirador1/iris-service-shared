#!/usr/bin/env bash
# =============================================================================
# bin/ship/pre-sync.sh — guard against `reset --hard` data loss.
#
# Universal git-safety check usable from any of the 4 mirador1 repos
# (java / python / ui / shared). When sourced via the submodule (consumer
# repos run it as `infra/shared/bin/ship/pre-sync.sh`) it operates on the
# CONSUMER's git state, not on shared's — `git rev-parse` reads from
# the working dir, not the script's location.
#
# Why this exists : sessions have lost work 3× in 2026-04 to the pattern
#   git reset --hard origin/main && git push --force-with-lease origin dev
# run while local dev still had unpushed commits OR uncommitted files.
# Recovery via `git reflog` works but burns 5+ min and risks a second
# mistake. Prevention is one extra command.
#
# Usage (run before ANY `reset --hard` you're about to do) :
#   bin/ship/pre-sync.sh                     # (in shared repo)
#   infra/shared/bin/ship/pre-sync.sh        # (in consumer repo)
#
# Exit code : 0 if safe to reset, 1 otherwise.
#
# Checks :
#   1. Uncommitted files in working tree (staged or not)
#   2. Untracked files (excluding gitignored)
#   3. Unpushed commits on the current branch (vs upstream)
#   4. Stash entries (informational warning, not blocking)
# =============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()  { echo -e "${DIM}▸${NC} $*"; }
ok()    { echo -e "  ${GREEN}✓${NC} $*"; }
warn()  { echo -e "  ${YELLOW}!${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; }

problems=0

current=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || {
  echo "Not in a git repo." >&2
  exit 2
}

info "Pre-sync check on branch '$current'"

# 1. Uncommitted files (staged + unstaged)
if [[ -n "$(git status --porcelain | grep -v '^??')" ]]; then
  fail "Uncommitted changes:"
  git status --short | grep -v '^??' | sed 's/^/      /'
  echo -e "    ${DIM}fix: \`git stash push -u -m pre-sync-stash\` then re-run${NC}"
  problems=$((problems + 1))
else
  ok "Working tree clean (no modified files)"
fi

# 2. Untracked files (only count those NOT in .gitignore)
untracked=$(git ls-files --others --exclude-standard)
if [[ -n "$untracked" ]]; then
  fail "Untracked files (not in .gitignore):"
  echo "$untracked" | sed 's/^/      /'
  echo -e "    ${DIM}fix: \`git add\` and commit, or \`git stash -u\`, or rm if disposable${NC}"
  problems=$((problems + 1))
else
  ok "No untracked files outside .gitignore"
fi

# 3. Unpushed commits vs upstream
upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || echo "")
if [[ -z "$upstream" ]]; then
  warn "No upstream tracking branch for '$current' — skipping unpushed-commits check."
else
  ahead_count=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)
  if [[ "$ahead_count" -gt 0 ]]; then
    fail "$ahead_count unpushed commits on '$current':"
    git log "${upstream}..HEAD" --oneline | sed 's/^/      /'
    echo -e "    ${DIM}fix: \`git push origin $current\` first (or note SHAs to cherry-pick after reset)${NC}"
    problems=$((problems + 1))
  else
    ok "No unpushed commits (synced with $upstream)"
  fi
fi

# 4. Stash entries (informational)
stash_count=$(git stash list | wc -l | tr -d ' ')
if [[ "$stash_count" -gt 0 ]]; then
  warn "$stash_count stash entries exist (not blocking, but easy to forget):"
  git stash list | head -3 | sed 's/^/      /'
fi

echo ""
if [[ "$problems" -gt 0 ]]; then
  echo -e "${RED}${BOLD}NOT SAFE${NC} — fix the $problems item(s) above before running \`git reset --hard\`."
  exit 1
fi
echo -e "${GREEN}${BOLD}SAFE${NC} — you can run \`git reset --hard\` without losing work."
exit 0
