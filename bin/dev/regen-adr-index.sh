#!/usr/bin/env bash
# =============================================================================
# bin/dev/regen-adr-index.sh — auto-regenerate the ADR flat index table.
#
# Universal version usable from any mirador1 repo. Scans the consumer's
# `docs/adr/[0-9][0-9][0-9][0-9]-*.md` files (resolved via `git rev-parse
# --show-toplevel`, NOT relative to the script's location, so it works
# both when called directly in shared AND when called via the submodule
# from a consumer repo).
#
# The generated block sits between marker comments in README.md :
#
#     <!-- ADR-INDEX:START -->
#     | ID | Status | Title |
#     |---|---|---|
#     | 0001 | Accepted | [Title](0001-slug.md) |
#     ...
#     <!-- ADR-INDEX:END -->
#
# Status detection accepts three formats observed across the 4 repos :
#   1. "- Status: X"             (Java-side bullet)
#   2. "- **Status**: X"         (Java-side bullet, bold)
#   3. "**Status** : X"          (Python + shared, no bullet, space-colon)
#
# Usage:
#   bin/dev/regen-adr-index.sh              # print generated table to stdout
#   bin/dev/regen-adr-index.sh --in-place   # replace between markers in README.md
#   bin/dev/regen-adr-index.sh --check      # exit 1 if drift detected (CI mode)
# =============================================================================

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
ADR_DIR="${REPO_ROOT}/docs/adr"
README="${ADR_DIR}/README.md"
MARKER_START="<!-- ADR-INDEX:START -->"
MARKER_END="<!-- ADR-INDEX:END -->"

mode="print"
case "${1:-}" in
    --in-place) mode="in-place" ;;
    --check)    mode="check" ;;
    --help|-h)
        sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //; s/^#//'
        exit 0
        ;;
    "") ;;
    *)
        echo "Unknown arg: $1" >&2
        exit 2
        ;;
esac

generate_table() {
    printf '| ID | Status | Title |\n'
    printf '|---|---|---|\n'

    for f in "${ADR_DIR}"/[0-9][0-9][0-9][0-9]-*.md; do
        [ -f "$f" ] || continue
        local filename id title status sup_by_link sup_by_file link_suffix

        filename="$(basename "$f")"
        id="${filename:0:4}"

        # Skip the template file (0000-template.md) — scaffold, not a real ADR.
        [ "$id" = "0000" ] && continue

        # Title — strip leading "# ADR-NNNN — ", "# ADR-NNNN: ", or "# ADR-NNNN " from first heading.
        title="$(head -1 "$f" \
            | sed -E 's/^#[[:space:]]*//' \
            | sed -E 's/^ADR-[0-9]{4}[[:space:]]*[—:-]+[[:space:]]*//' \
            | sed -E 's/^ADR-[0-9]{4}:[[:space:]]*//')"

        # Status — accepts three formats (see header).
        status="$( { grep -m1 -iE '^(-[[:space:]]+)?(\*\*)?Status(\*\*)?[[:space:]]*:' "$f" || true; } \
            | sed -E 's/^(-[[:space:]]+)?(\*\*)?Status(\*\*)?[[:space:]]*:[[:space:]]*//' \
            | sed -E 's/\*\*//g' \
            | awk '{print $1}')"
        [ -z "$status" ] && status="Unknown"

        # Superseded-by link — only when status="Superseded" + body has "Superseded by [ADR-XXXX](XXXX-slug.md)".
        link_suffix=""
        if [ "$status" = "Superseded" ]; then
            local sup_line
            sup_line="$(grep -iE 'Superseded by' "$f" | head -1 || true)"
            sup_by_link="$(printf '%s' "$sup_line" | grep -oE 'ADR-[0-9]{4}' | head -1 || true)"
            sup_by_file="$(printf '%s' "$sup_line" | grep -oE '[0-9]{4}-[a-z0-9-]+\.md' | head -1 || true)"
            if [ -n "$sup_by_link" ] && [ -n "$sup_by_file" ]; then
                link_suffix=" → [${sup_by_link}](${sup_by_file})"
            fi
        fi

        printf '| %s | %s | [%s](%s)%s |\n' "$id" "$status" "$title" "$filename" "$link_suffix"
    done
}

check_drift() {
    if ! grep -qF "$MARKER_START" "$README" || ! grep -qF "$MARKER_END" "$README"; then
        echo "ERROR: ADR-INDEX markers missing from $README" >&2
        echo "Add these two lines around the flat-index table:" >&2
        echo "  $MARKER_START" >&2
        echo "  $MARKER_END" >&2
        exit 2
    fi

    local current expected
    current="$(awk -v s="$MARKER_START" -v e="$MARKER_END" \
        'BEGIN{p=0} $0==s{p=1; next} $0==e{p=0} p{print}' "$README")"
    expected="$(generate_table)"

    if [ "$current" = "$expected" ]; then
        echo "OK — ADR index in $README matches generated content."
        exit 0
    else
        echo "DRIFT — ADR index in $README differs from generated content." >&2
        echo "Run: bin/dev/regen-adr-index.sh --in-place" >&2
        diff <(printf '%s\n' "$current") <(printf '%s\n' "$expected") || true
        exit 1
    fi
}

in_place() {
    if ! grep -qF "$MARKER_START" "$README" || ! grep -qF "$MARKER_END" "$README"; then
        echo "ERROR: ADR-INDEX markers missing from $README — add them first." >&2
        exit 2
    fi

    local tmp_table tmp_readme
    tmp_table="$(mktemp)"
    tmp_readme="$(mktemp)"
    generate_table > "$tmp_table"

    awk -v s="$MARKER_START" -v e="$MARKER_END" -v tf="$tmp_table" '
        BEGIN { p=1 }
        $0 == s {
            print
            while ((getline line < tf) > 0) print line
            close(tf)
            p = 0
            next
        }
        $0 == e { p = 1 }
        p { print }
    ' "$README" > "$tmp_readme"
    mv "$tmp_readme" "$README"
    rm -f "$tmp_table"
    echo "Updated $README — flat index regenerated from $(ls "${ADR_DIR}"/[0-9][0-9][0-9][0-9]-*.md | wc -l | tr -d ' ') ADR files."
}

case "$mode" in
    print)    generate_table ;;
    in-place) in_place ;;
    check)    check_drift ;;
esac
