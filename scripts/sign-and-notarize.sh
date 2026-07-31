#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

APP_NAME="${APP_NAME:-MidiTapTempoIndicator}"
APP_PATH="${APP_PATH:-${ROOT}/dist/${APP_NAME}.app}"
ENTITLEMENTS="${ENTITLEMENTS:-${ROOT}/Resources/MidiTapTempoIndicator.entitlements}"
MACOS_SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:?MACOS_SIGNING_IDENTITY is required}"
APP_STORE_CONNECT_API_KEY_PATH="${APP_STORE_CONNECT_API_KEY_PATH:-}"
APP_STORE_CONNECT_API_KEY_ID="${APP_STORE_CONNECT_API_KEY_ID:-}"
APP_STORE_CONNECT_API_ISSUER_ID="${APP_STORE_CONNECT_API_ISSUER_ID:-}"

usage() {
    cat <<EOF
Usage: $(basename "$0")

Sign and notarize an existing .app bundle for distribution.

Required environment:
  MACOS_SIGNING_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"

Optional environment:
  APP_PATH                 Path to .app (default: dist/MidiTapTempoIndicator.app)
  ENTITLEMENTS             Path to entitlements plist
  APP_STORE_CONNECT_API_KEY_PATH
                           Path to the App Store Connect API .p8 key
  APP_STORE_CONNECT_API_KEY_ID
                           App Store Connect API key ID
  APP_STORE_CONNECT_API_ISSUER_ID
                           App Store Connect API issuer ID
  SKIP_NOTARIZE            Set to "true" to sign only
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found at ${APP_PATH}" >&2
    exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
    echo "error: entitlements file not found at ${ENTITLEMENTS}" >&2
    exit 1
fi

echo "==> Signing ${APP_PATH}..."
codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
    --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ARCHIVE_PATH="${RUNNER_TEMP:-/tmp}/$(basename "$APP_PATH" .app).zip"
echo "==> Creating archive ${ARCHIVE_PATH}..."
ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE_PATH"

if [[ "${SKIP_NOTARIZE:-false}" == "true" ]]; then
    echo "Skipping notarization (SKIP_NOTARIZE=true)"
    echo "ARCHIVE_PATH=${ARCHIVE_PATH}"
    exit 0
fi

if [[ -z "$APP_STORE_CONNECT_API_KEY_PATH" || -z "$APP_STORE_CONNECT_API_KEY_ID" || -z "$APP_STORE_CONNECT_API_ISSUER_ID" ]]; then
    echo "error: App Store Connect API key path, key ID, and issuer ID are required for notarization" >&2
    exit 1
fi

echo "==> Submitting to Apple notarization..."
xcrun notarytool submit "$ARCHIVE_PATH" \
    --key "$APP_STORE_CONNECT_API_KEY_PATH" \
    --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_API_ISSUER_ID" \
    --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "ARCHIVE_PATH=${ARCHIVE_PATH}"
