#!/usr/bin/env bash
# renovate-sync.sh — sync common Renovate config from shared/renovate-base.json
# into each mirador1 repo's renovate.json.
#
# Strategy : the shared base file holds the keys that are common across all
# 4 repos (extends, timezone, labels, prHourlyLimit, vulnerabilityAlerts,
# lockFileMaintenance, common packageRules). Each repo's renovate.json
# keeps ONLY its repo-specific packageRules (FastAPI groups for python,
# Spring Boot for java, Angular for ui, K8s for shared). After sync :
#
#     final = base ⊔ repo-specific
#     final.packageRules = base.packageRules + repo.packageRules
#
# This is option B from session 2026-04-25 (script sync vs hosted Renovate
# preset). Pros : no network preset hosting, no Renovate config validation
# round-trip, repo-specific rules stay readable in their own file.
#
# Run :
#   bin/ship/renovate-sync.sh                # all 4 repos, write diffs
#   bin/ship/renovate-sync.sh --check        # dry-run, exit 1 if drift
#   bin/ship/renovate-sync.sh --repo python  # one repo only
#
# CI hook : a `renovate-sync-check` lint job in each repo's CI runs
# `bin/ship/renovate-sync.sh --check` (script lives in shared submodule
# at infra/shared/bin/ship/renovate-sync.sh).

set -euo pipefail

# ── Repos ────────────────────────────────────────────────────────────────────
declare -A REPO_PATHS=(
    [java]="/Users/benoitbesson/dev/workspace-modern/mirador-service-java"
    [python]="/Users/benoitbesson/dev/workspace-modern/mirador-service-python"
    [ui]="/Users/benoitbesson/dev/js/mirador-ui"
    [shared]="/Users/benoitbesson/dev/workspace-modern/mirador-service-shared"
)

# Locate base file (relative to this script — works whether script lives in
# shared/bin/ship/ OR in <repo>/infra/shared/bin/ship/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_FILE="$SCRIPT_DIR/../../renovate-base.json"
if [ ! -f "$BASE_FILE" ]; then
    echo "❌ renovate-base.json not found at $BASE_FILE"
    exit 2
fi

# ── Args ─────────────────────────────────────────────────────────────────────
CHECK_ONLY=0
ONLY_REPO=""
for arg in "$@"; do
    case "$arg" in
        --check) CHECK_ONLY=1 ;;
        --repo) shift ; ONLY_REPO="$1" ; shift ;;
        --repo=*) ONLY_REPO="${arg#--repo=}" ;;
    esac
done

# ── Strip _comment fields from base BEFORE merging ───────────────────────────
# Renovate accepts unknown keys but flags them in logs ; we use _comment
# as inline doc but strip it from the actual repo file.
strip_comments() {
    jq 'walk(if type=="object" then with_entries(select(.key != "_comment")) else . end)'
}

BASE_CLEAN=$(strip_comments < "$BASE_FILE")

# ── Per-repo sync ────────────────────────────────────────────────────────────
exit_code=0
for repo in "${!REPO_PATHS[@]}"; do
    [ -n "$ONLY_REPO" ] && [ "$repo" != "$ONLY_REPO" ] && continue

    repo_path="${REPO_PATHS[$repo]}"
    repo_renovate="$repo_path/renovate.json"
    if [ ! -f "$repo_renovate" ]; then
        echo "⚠ $repo : no renovate.json at $repo_renovate — skipping"
        continue
    fi

    # Extract repo-specific packageRules : everything in the existing
    # renovate.json that has a `groupName` (= a domain group like
    # "FastAPI / Pydantic stack" or "Spring Boot"). Generic rules
    # (auto-merge patch/minor/digest, Docker pinDigests, SNAPSHOT block)
    # come from the base file.
    REPO_SPECIFIC_RULES=$(jq '
        .packageRules // []
        | map(select(has("groupName")))
    ' "$repo_renovate")

    # Also keep the gitlabci block + description if present.
    REPO_GITLABCI=$(jq '.gitlabci // null' "$repo_renovate")
    REPO_DESCRIPTION=$(jq '.description // null' "$repo_renovate")

    # Merge : base + repo-specific overrides
    MERGED=$(echo "$BASE_CLEAN" | jq \
        --argjson rules "$REPO_SPECIFIC_RULES" \
        --argjson gitlabci "$REPO_GITLABCI" \
        --argjson description "$REPO_DESCRIPTION" \
        '
        .packageRules += $rules
        | if $gitlabci then . + {gitlabci: $gitlabci} else . end
        | if $description then . + {description: $description} else . end
        ')

    if [ "$CHECK_ONLY" = "1" ]; then
        DIFF=$(diff <(jq -S . "$repo_renovate") <(echo "$MERGED" | jq -S .) || true)
        if [ -n "$DIFF" ]; then
            echo "❌ $repo : drift detected"
            echo "$DIFF" | head -20
            echo "  → run bin/ship/renovate-sync.sh (without --check) to apply"
            exit_code=1
        else
            echo "✓ $repo : in sync"
        fi
    else
        echo "$MERGED" | jq . > "$repo_renovate.tmp"
        mv "$repo_renovate.tmp" "$repo_renovate"
        echo "✓ $repo : renovate.json updated ($(jq '.packageRules | length' "$repo_renovate") packageRules total)"
    fi
done

exit $exit_code
