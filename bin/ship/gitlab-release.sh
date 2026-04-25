#!/usr/bin/env bash
# =============================================================================
# bin/ship/gitlab-release.sh — promote a `stable-v*` git tag to a GitLab
# Release at /-/releases.
#
# Why a script instead of a CI job: the CI job approach (GitLab release-cli)
# requires opening the workflow:rules to tag pushes, which then triggers
# the heavy security + docker-build jobs on every tag (15-30 min, free
# runner time). With ~3-6 stable-v* tags per dev day this would burn a
# pipeline per tag for no extra validation (the pre-merge MR pipeline
# already validated the commit). A local script after `git push <tag>`
# costs 1 second and creates the same Release object.
#
# Usage:
#   bin/ship/gitlab-release.sh stable-v1.0.18                 # current repo
#   bin/ship/gitlab-release.sh stable-v1.0.18 --notes-from-tag # use tag's
#                                                              # annotated msg
#
# Defaults: notes = annotated tag message (`git tag -l --format='%(contents)'`).
# Override with --notes "..." for a custom description.
#
# Both repos: this script is meant for `mirador-service`; the sibling UI
# repo (`mirador-ui`) ships an identical copy. Tag both together when a
# stable checkpoint spans both.
#
# Related:
#   - ~/.claude/CLAUDE.md → "Tag every green stability checkpoint, never
#     tag on red" — the contract this script enforces (after tag exists,
#     the Release just mirrors it).
#   - bin/cluster/demo/up.sh — release infra docs lives in the runbooks.
# =============================================================================
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 <tag> [--notes "..." | --notes-from-tag]

Promote a git tag to a GitLab Release.

Arguments:
  <tag>              Required. Annotated git tag (e.g. stable-v1.0.18).

Options:
  --notes "TEXT"     Use TEXT as the release description.
  --notes-from-tag   Use the annotated tag's message as the description (default).
  --help, -h         Show this help.

Prerequisite:
  - Tag must exist locally AND on origin (push it first).
  - glab CLI authenticated (see glab auth status).

Example:
  git tag -a stable-v1.0.18 -m "Stability checkpoint — phase B-6 done"
  git push origin stable-v1.0.18
  bin/ship/gitlab-release.sh stable-v1.0.18
EOF
}

if [ $# -lt 1 ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage; exit 0
fi

TAG="$1"
shift
NOTES_MODE="from-tag"
NOTES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --notes) NOTES="$2"; NOTES_MODE="custom"; shift 2 ;;
    --notes-from-tag) NOTES_MODE="from-tag"; shift ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# Sanity: tag exists locally
if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "❌  Tag $TAG not found locally. Create it first with 'git tag -a $TAG -m \"...\"'."
  exit 1
fi

# Sanity: tag pushed to origin
if ! git ls-remote --tags origin "$TAG" 2>/dev/null | grep -q "$TAG"; then
  echo "❌  Tag $TAG not pushed to origin. Run 'git push origin $TAG' first."
  exit 2
fi

# Sanity: glab authenticated
if ! glab auth status >/dev/null 2>&1; then
  echo "❌  glab CLI not authenticated. Run 'glab auth login' first."
  exit 3
fi

# Resolve the description
if [ "$NOTES_MODE" = "from-tag" ]; then
  NOTES="$(git tag -l --format='%(contents)' "$TAG")"
  if [ -z "$NOTES" ]; then
    NOTES="Stability checkpoint — see git log $TAG for details."
  fi
fi

# Check if the release already exists (idempotent — re-running is safe)
if glab release view "$TAG" >/dev/null 2>&1; then
  echo "ℹ  Release $TAG already exists. Use 'glab release update $TAG' to modify."
  glab release view "$TAG" | head -10
  exit 0
fi

echo "▶️  Creating GitLab Release for ${TAG}…"
echo "   Notes:"
echo "$NOTES" | sed 's/^/     /'
echo ""

glab release create "$TAG" \
  --name "$TAG" \
  --notes "$NOTES" \
  --ref "$TAG"

echo ""
echo "✅ Release published. Visible at:"
glab repo view --web --no-browser 2>/dev/null | grep -oE 'https://[^ ]+' | head -1 | sed 's,$,/-/releases,'
