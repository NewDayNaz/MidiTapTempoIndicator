#!/usr/bin/env bash
set -euo pipefail

CURRENT_TAG="${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"
VERSION="${CURRENT_TAG#v}"
OUTPUT_PATH="${1:-release-notes.md}"

if PREVIOUS_TAG="$(git describe --tags --abbrev=0 "${CURRENT_TAG}^" 2>/dev/null)"; then
    LOG_RANGE="${PREVIOUS_TAG}..${CURRENT_TAG}"
    CHANGELOG_HEADER="Changes since ${PREVIOUS_TAG}"
else
    LOG_RANGE="${CURRENT_TAG}"
    CHANGELOG_HEADER="Changes"
fi

{
    echo "## MIDI Tap Tempo Indicator v${VERSION}"
    echo
    echo "Signed, notarized macOS build attached below."
    echo
    echo "### ${CHANGELOG_HEADER}"
    echo

    COMMIT_COUNT="$(git log "${LOG_RANGE}" --no-merges --format='%h' | wc -l | tr -d ' ')"
    if [[ "$COMMIT_COUNT" -eq 0 ]]; then
        echo "_No commits found for this release range._"
    else
        git log "${LOG_RANGE}" --no-merges --format='- `%h` %s'
    fi
} > "$OUTPUT_PATH"

echo "Wrote release notes to ${OUTPUT_PATH}"
