#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-0.1.0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="Local STT"
BUNDLE_ID="com.localtools.localstt"
ENTITLEMENTS="$SCRIPT_DIR/LocalSTT.entitlements"

echo "==> Building LocalSTT v${VERSION}"

# ── Phase 1: Build ──────────────────────────────────────────────
echo "==> Phase 1: swift build -c release"
cd "$PROJECT_DIR"
swift build -c release

BINARY="$PROJECT_DIR/.build/release/LocalSTT"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Release binary not found at $BINARY"
    exit 1
fi

# ── Phase 2: Bundle ─────────────────────────────────────────────
echo "==> Phase 2: Assembling ${APP_NAME}.app"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY" "$MACOS_DIR/LocalSTT"

# Generate Info.plist
cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Local STT</string>
    <key>CFBundleDisplayName</key>
    <string>Local STT</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>LocalSTT</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Local STT needs microphone access to transcribe your speech on-device.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 Local STT. All rights reserved.</string>
</dict>
</plist>
PLIST

# Copy app icon if present
ICON_PATH="$PROJECT_DIR/Sources/Resources/AppIcon.icns"
if [ -f "$ICON_PATH" ]; then
    cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"
    # Add icon key to Info.plist (insert before closing </dict>)
    sed -i '' 's|</dict>|    <key>CFBundleIconFile</key>\
    <string>AppIcon</string>\
</dict>|' "$CONTENTS/Info.plist"
    echo "    Bundled AppIcon.icns"
fi

echo "    ${APP_NAME}.app assembled"

# ── Phase 3: Sign ───────────────────────────────────────────────
if [ "$CODESIGN_IDENTITY" = "-" ]; then
    echo "==> Phase 3: Ad-hoc code signing (no CODESIGN_IDENTITY set)"
    codesign --force --deep \
        --sign - \
        "$APP_DIR"
else
    echo "==> Phase 3: Code signing with identity: ${CODESIGN_IDENTITY}"
    # Hardened runtime + entitlements required for notarization
    codesign --force --deep \
        --sign "$CODESIGN_IDENTITY" \
        --options runtime \
        --entitlements "$ENTITLEMENTS" \
        "$APP_DIR"
fi

echo "    Signed"

# ── Phase 4: DMG ────────────────────────────────────────────────
echo "==> Phase 4: Creating DMG"
DMG_NAME="LocalSTT-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING="$DIST_DIR/dmg-staging"

rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"

cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -srcfolder "$STAGING" \
    -volname "Local STT" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

rm -rf "$STAGING"

echo ""
echo "==> Done: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
