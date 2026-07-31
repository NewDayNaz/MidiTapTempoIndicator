#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

APP_NAME="MidiTapTempoIndicator"
DISPLAY_NAME="MIDI Tap Tempo Indicator"
BUNDLE_ID="com.newdaynaz.miditaptempoindicator"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MIN_MACOS="13.0"
SKIP_SIGN="${SKIP_SIGN:-false}"
MACOS_SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-}"
ENTITLEMENTS="${ENTITLEMENTS:-${ROOT}/Resources/MidiTapTempoIndicator.entitlements}"

OUTPUT_DIR="${ROOT}/dist"
APP_PATH="${OUTPUT_DIR}/${APP_NAME}.app"
INSTALL=false
OPEN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build ${DISPLAY_NAME} as a macOS .app bundle in dist/

Options:
  --install       Copy the app to /Applications after building
  --open          Launch the app after building
  -h, --help      Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            INSTALL=true
            shift
            ;;
        --open)
            OPEN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

cd "$ROOT"

# shellcheck source=ensure-swift-build-root.sh
source "$(dirname "$0")/ensure-swift-build-root.sh"
ensure_swift_build_root "$ROOT"

echo "==> Preparing icons..."
bash "$(dirname "$0")/generate-menu-bar-icon.sh"

echo "==> Building release binary..."
swift build -c release
BINARY_DIR="$(swift build -c release --show-bin-path)"
BINARY="${BINARY_DIR}/${APP_NAME}"
RESOURCE_BUNDLE="${BINARY_DIR}/${APP_NAME}_${APP_NAME}.bundle"
if [[ ! -f "$BINARY" ]]; then
    echo "error: binary not found at ${BINARY}" >&2
    exit 1
fi
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "error: resource bundle not found at ${RESOURCE_BUNDLE}" >&2
    exit 1
fi

echo "==> Creating app bundle..."
rm -rf "$APP_PATH"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

cp "${ROOT}/Resources/MenuBarIcon.png" "${APP_PATH}/Contents/Resources/MenuBarIcon.png"
cp "${ROOT}/Resources/MenuBarIcon@2x.png" "${APP_PATH}/Contents/Resources/MenuBarIcon@2x.png"
cp -R "$RESOURCE_BUNDLE" "${APP_PATH}/Contents/Resources/${APP_NAME}_${APP_NAME}.bundle"

cp "$BINARY" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_PATH}/Contents/MacOS/${APP_NAME}"

cat > "${APP_PATH}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © $(date +%Y). All rights reserved.</string>
</dict>
</plist>
EOF

if [[ "$SKIP_SIGN" == "true" ]]; then
    echo "==> Skipping codesign (SKIP_SIGN=true)"
elif command -v codesign >/dev/null 2>&1; then
    if [[ -n "$MACOS_SIGNING_IDENTITY" ]]; then
        echo "==> Signing app with Developer ID..."
        if [[ ! -f "$ENTITLEMENTS" ]]; then
            echo "error: entitlements file not found at ${ENTITLEMENTS}" >&2
            exit 1
        fi
        codesign --force --options runtime --entitlements "$ENTITLEMENTS" \
            --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$APP_PATH"
    else
        echo "==> Signing app (ad-hoc)..."
        codesign --force --sign - --timestamp=none "$APP_PATH"
    fi
else
    echo "warning: codesign not found, skipping signature" >&2
fi

echo ""
echo "Built: ${APP_PATH}"
echo "Launch at login is available when running the .app bundle."

if $INSTALL; then
    TARGET="/Applications/${APP_NAME}.app"
    echo "==> Installing to ${TARGET}..."
    rm -rf "$TARGET"
    cp -R "$APP_PATH" "$TARGET"
    if command -v codesign >/dev/null 2>&1; then
        codesign --force --sign - --timestamp=none "$TARGET"
    fi
    echo "Installed: ${TARGET}"
fi

if $OPEN; then
    open "$APP_PATH"
fi
