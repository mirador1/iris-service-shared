#!/usr/bin/env bash
# check-default-branch.sh — verifies all mirador1 projects have
# default_branch=main, NOT dev or any other.
#
# Why this exists : 2026-04-25 we lost ~30 min debugging "post-merge main
# pipelines never trigger" on mirador-service-python. Root cause :
# default_branch was 'dev' (set incorrectly during repo creation). The
# workflow:rules `$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH` then matched
# dev pushes (= the working branch — fine) BUT didn't match merge
# commits to main → silent missing pipelines.
#
# This is a category-1 silent failure — nothing obvious points to it,
# pipelines just don't appear. The fix is one API call ; the discovery
# took an interactive debug session. This script is the prevention.
#
# Run :
#   bin/ship/check-default-branch.sh
#
# Exit 0 if all 4 projects have default_branch=main.
# Exit 1 if any project is misconfigured (prints which + the fix command).
#
# CI : wired into bin/dev/stability-check.sh (preflight section) so a
# misconfig surfaces on the next stability checkpoint, not the next
# silent merge.

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
PROJECTS=(
    "mirador1/mirador-service-java"
    "mirador1/mirador-ui"
    "mirador1/mirador-service-python"
    "mirador1/mirador-service-shared"
)
EXPECTED_BRANCH="main"

# ── Token resolution ─────────────────────────────────────────────────────────
# Reuse glab's stored token to avoid re-prompting.
TOKEN_FILE="$HOME/Library/Application Support/glab-cli/config.yml"
if [ ! -f "$TOKEN_FILE" ]; then
    echo "❌ glab not configured ; install + login : brew install glab && glab auth login"
    exit 2
fi
TOKEN="$(grep -E '^\s*token:' "$TOKEN_FILE" | head -1 | awk '{print $NF}')"
if [ -z "$TOKEN" ]; then
    echo "❌ Could not extract token from $TOKEN_FILE"
    exit 2
fi

# ── Check loop ───────────────────────────────────────────────────────────────
fail=0
for proj in "${PROJECTS[@]}"; do
    encoded="${proj//\//%2F}"
    actual=$(curl -s -H "PRIVATE-TOKEN: $TOKEN" \
        "https://gitlab.com/api/v4/projects/$encoded" 2>/dev/null \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('default_branch','?'))")

    if [ "$actual" = "$EXPECTED_BRANCH" ]; then
        printf "  ✓ %-45s default_branch=%s\n" "$proj" "$actual"
    else
        printf "  ❌ %-45s default_branch=%s (expected %s)\n" "$proj" "$actual" "$EXPECTED_BRANCH"
        printf "     fix : glab api --method PUT 'projects/%s' -F default_branch=%s\n" \
            "$encoded" "$EXPECTED_BRANCH"
        fail=$((fail + 1))
    fi
done

if [ $fail -gt 0 ]; then
    echo ""
    echo "❌ $fail project(s) misconfigured. Symptom : merge commits on main"
    echo "   never trigger pipelines because workflow:rules matches the"
    echo "   wrong default_branch. See script header for full rationale."
    exit 1
fi

echo ""
echo "✓ All ${#PROJECTS[@]} projects have default_branch=$EXPECTED_BRANCH."
