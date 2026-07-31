#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Validating shell scripts..."
while IFS= read -r script; do
    echo "  bash -n ${script#./}"
    bash -n "$script"
done < <(find scripts -name '*.sh' -print | sort)

echo "==> Linting entitlements..."
plutil -lint Resources/MidiTapTempoIndicator.entitlements

echo "==> Building debug..."
swift build

echo "==> Running unit tests..."
swift test

echo "==> Building release app bundle..."
./scripts/build-app.sh

echo "==> Verifying app bundle..."
./scripts/verify-bundle.sh

echo "CI verification passed."
