#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${APP_PATH:-${ROOT}/dist/MidiTapTempoIndicator.app}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.newdaynaz.miditaptempoindicator}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: app bundle not found at ${APP_PATH}" >&2
    exit 1
fi

EXECUTABLE="${APP_PATH}/Contents/MacOS/MidiTapTempoIndicator"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"

echo "==> Checking executable..."
test -x "$EXECUTABLE"
file "$EXECUTABLE" | grep -q "Mach-O"

echo "==> Linting Info.plist..."
plutil -lint "$INFO_PLIST"

read_plist() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

echo "==> Checking bundle metadata..."
[[ "$(read_plist CFBundleIdentifier)" == "$EXPECTED_BUNDLE_ID" ]]
[[ "$(read_plist LSUIElement)" == "true" ]]

MIN_VERSION="$(read_plist LSMinimumSystemVersion)"
echo "Minimum macOS version: ${MIN_VERSION}"

echo "==> Checking bundled resources..."
for resource in MenuBarIcon.png MenuBarIcon@2x.png MidiTapTempoIndicator_MidiTapTempoIndicator.bundle; do
    if [[ ! -e "${APP_PATH}/Contents/Resources/${resource}" ]]; then
        echo "error: missing resource ${resource}" >&2
        exit 1
    fi
done

echo "==> Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Bundle verification passed for ${APP_PATH}"
