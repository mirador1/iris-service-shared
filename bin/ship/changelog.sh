#!/usr/bin/env bash
# =============================================================================
# bin/ship/changelog.sh — auto-update CHANGELOG.md from Conventional Commits.
#
# Universal version usable from any mirador1 repo (java / python / ui /
# shared). Each consumer passes its own tag prefix via `--tag-prefix` so
# the script reads the right tag space :
#
#   Java   : --tag-prefix stable-v       (stable-v1.2.3)
#   Python : --tag-prefix stable-py-v    (stable-py-v0.7.0)
#   UI     : --tag-prefix stable-v       (stable-v1.0.5)
#   Shared : --tag-prefix shared-v       (shared-v0.1.0 — if ever tagged)
#
# Default is `stable-v` to preserve historical Java behaviour for
# zero-arg invocations.
#
# Replacement for release-please (which was GitHub-API-only and failed on
# GitLab — see ADR-0055). Hand-rolled bash, no external deps beyond `git`.
#
# Categorisation follows the same convention as release-please :
#   feat:     → ✨ Features
#   fix:      → 🐛 Bug fixes
#   perf:     → ⚡ Performance
#   refactor: → ♻️  Refactoring
#   docs:     → 📚 Documentation
#   test:     → 🧪 Tests
#   chore:    → 🔧 Chore (filtered by default — pass --include-chore to keep)
#   ci:       → 👷 CI (filtered by default)
#   build:    → 📦 Build (filtered by default)
#   style:    → 💄 Style (filtered by default)
#   <other>   → 📌 Other
#
# Breaking changes (BREAKING CHANGE: ... in commit body OR feat!: prefix)
# get a 💥 prefix on the line.
#
# Usage :
#   bin/ship/changelog.sh                            # default tag-prefix=stable-v, writes to CHANGELOG.md
#   bin/ship/changelog.sh --tag-prefix stable-py-v   # Python repo
#   bin/ship/changelog.sh --since v1.0.30            # custom range start
#   bin/ship/changelog.sh --include-chore            # include chore/ci/build/style sections
#   bin/ship/changelog.sh --dry-run                  # print to stdout, don't write
#
# Used as : infra/shared/bin/ship/changelog.sh --tag-prefix stable-py-v
# (consumer repos call it via the submodule path).
#
# After updating CHANGELOG.md :
#   git add CHANGELOG.md && git commit -m "chore(changelog): bump for vX.Y.Z"
#   git tag -a <tag-prefix><X.Y.Z> -m "..."
#   git push origin <tag-prefix><X.Y.Z>
#   bin/ship/gitlab-release.sh <tag-prefix><X.Y.Z>
# =============================================================================
set -euo pipefail

INCLUDE_CHORE=0
DRY_RUN=0
SINCE=""
TAG_PREFIX="stable-v"

while [ $# -gt 0 ]; do
  case "$1" in
    --include-chore)   INCLUDE_CHORE=1 ; shift ;;
    --dry-run)         DRY_RUN=1 ; shift ;;
    --since)           SINCE="$2" ; shift 2 ;;
    --since=*)         SINCE="${1#--since=}" ; shift ;;
    --tag-prefix)      TAG_PREFIX="$2" ; shift 2 ;;
    --tag-prefix=*)    TAG_PREFIX="${1#--tag-prefix=}" ; shift ;;
    --help|-h)
      sed -n '2,40p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1 (use --help)" >&2
      exit 1
      ;;
  esac
done

# Default range : since the latest <tag-prefix>* tag.
if [ -z "$SINCE" ]; then
  SINCE=$(git tag -l "${TAG_PREFIX}*" | sort -V | tail -1)
  if [ -z "$SINCE" ]; then
    echo "❌ No ${TAG_PREFIX}* tag found ; pass --since <ref>" >&2
    exit 1
  fi
fi

NEXT_VER="$(date +%Y-%m-%d)-unreleased"

echo "▸ Generating CHANGELOG entries since $SINCE..." >&2

# Categorisation function — outputs `<emoji-section>|<message>` per commit.
# Handles both `<type>: msg` and `<type>(scope): msg` Conventional Commits forms.
classify() {
  local subj="$1"
  # Strip optional (scope) and trailing colon to get just the type.
  local type
  type=$(echo "$subj" | sed -E 's/^([a-z]+)(\([^)]*\))?(!)?:.*/\1\3/')
  case "$type" in
    feat!|*BREAKING*)    echo "💥 Breaking|${subj}" ;;
    feat)                echo "✨ Features|${subj#*: }" ;;
    fix)                 echo "🐛 Bug fixes|${subj#*: }" ;;
    perf)                echo "⚡ Performance|${subj#*: }" ;;
    refactor)            echo "♻️  Refactoring|${subj#*: }" ;;
    docs)                echo "📚 Documentation|${subj#*: }" ;;
    test)                echo "🧪 Tests|${subj#*: }" ;;
    # `|| true` is required : `set -e` is on, and `[ 0 -eq 1 ]` returns
    # exit code 1, which kills `cls=$(classify ...)` callers immediately
    # when --include-chore is off. Without the `|| true`, the script
    # exits silently the first time it sees a chore/ci/build/style
    # commit, producing no output (observed 2026-04-23 — fix below).
    chore)               { [ "$INCLUDE_CHORE" -eq 1 ] && echo "🔧 Chore|${subj#*: }"; } || true ;;
    ci)                  { [ "$INCLUDE_CHORE" -eq 1 ] && echo "👷 CI|${subj#*: }"; }    || true ;;
    build)               { [ "$INCLUDE_CHORE" -eq 1 ] && echo "📦 Build|${subj#*: }"; } || true ;;
    style)               { [ "$INCLUDE_CHORE" -eq 1 ] && echo "💄 Style|${subj#*: }"; } || true ;;
    *)                   echo "📌 Other|${subj}" ;;
  esac
}

# Group commits by section, output Markdown.
NEW_ENTRY=$(mktemp)
{
  echo "## $NEXT_VER (since [$SINCE](../../tags/$SINCE))"
  echo ""

  # First pass : collect categorised entries.
  CAT_FILE=$(mktemp)
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    sha=$(echo "$line" | cut -d'|' -f1)
    subj=$(echo "$line" | cut -d'|' -f2-)
    cls=$(classify "$subj")
    [ -z "$cls" ] && continue
    section=$(echo "$cls" | cut -d'|' -f1)
    msg=$(echo "$cls" | cut -d'|' -f2-)
    echo "$section|$sha|$msg" >> "$CAT_FILE"
  done < <(git log "$SINCE..HEAD" --no-merges --format='%h|%s')

  # Second pass : emit per-section. Order matters (most important first).
  for section in "💥 Breaking" "✨ Features" "🐛 Bug fixes" "⚡ Performance" "♻️  Refactoring" "📚 Documentation" "🧪 Tests" "🔧 Chore" "👷 CI" "📦 Build" "💄 Style" "📌 Other"; do
    # Plain `grep` (regex). Earlier `grep -F "^…|"` was buggy : -F treats
    # `^` and `|` as literal characters, never matches → first attempt
    # always failed, fell through to plain grep — but `set -e` + `$()`
    # tripped the script before reaching the fallback. One grep, one path.
    matches=$(grep "^$section|" "$CAT_FILE" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      echo "### $section"
      echo ""
      while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        sha=$(echo "$entry" | cut -d'|' -f2)
        msg=$(echo "$entry" | cut -d'|' -f3-)
        echo "- $msg ([\`$sha\`](../../commits/$sha))"
      done <<< "$matches"
      echo ""
    fi
  done

  rm -f "$CAT_FILE"
} > "$NEW_ENTRY"

if [ "$DRY_RUN" -eq 1 ]; then
  cat "$NEW_ENTRY"
  rm -f "$NEW_ENTRY"
  exit 0
fi

# Prepend new entry to existing CHANGELOG.md (or create it).
TARGET="${CHANGELOG_PATH:-CHANGELOG.md}"
if [ ! -f "$TARGET" ]; then
  echo "# Changelog" > "$TARGET"
  echo "" >> "$TARGET"
fi

# Insert new entry after the "# Changelog" header (line 1).
TMP=$(mktemp)
{
  head -2 "$TARGET"
  cat "$NEW_ENTRY"
  tail -n +3 "$TARGET"
} > "$TMP"
mv "$TMP" "$TARGET"
rm -f "$NEW_ENTRY"

echo "✓ Updated $TARGET (entry prepended after header line)"
echo "▸ Review with : less $TARGET"
echo "▸ Commit with : git add $TARGET && git commit -m 'chore(changelog): bump for vX.Y.Z'"
