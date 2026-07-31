#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/Resources"
SPM_RESOURCES="${ROOT}/Sources/MidiTapTempoIndicator/Resources"

swift "${ROOT}/scripts/generate-menu-bar-icon.swift" "$OUT_DIR"

mkdir -p "$SPM_RESOURCES"
cp "${OUT_DIR}/MenuBarIcon.png" "${OUT_DIR}/MenuBarIcon@2x.png" "$SPM_RESOURCES/"

echo "Copied menu bar icons into ${SPM_RESOURCES}"
