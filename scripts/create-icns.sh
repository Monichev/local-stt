#!/bin/bash
# Convert Logo.png to AppIcon.icns for macOS app bundle
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_PNG="$ROOT_DIR/Sources/Resources/Logo.png"
OUTPUT_ICNS="$ROOT_DIR/Sources/Resources/AppIcon.icns"
ICONSET_DIR=$(mktemp -d)/AppIcon.iconset

mkdir -p "$ICONSET_DIR"

echo "Creating iconset from $SOURCE_PNG..."

sips -z 16 16     "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16.png"      > /dev/null
sips -z 32 32     "$SOURCE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"   > /dev/null
sips -z 32 32     "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32.png"      > /dev/null
sips -z 64 64     "$SOURCE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"   > /dev/null
sips -z 128 128   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128.png"    > /dev/null
sips -z 256 256   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256.png"    > /dev/null
sips -z 512 512   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512.png"    > /dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

echo "Converting iconset to icns..."
iconutil --convert icns "$ICONSET_DIR" --output "$OUTPUT_ICNS"

rm -rf "$(dirname "$ICONSET_DIR")"

echo "Created $OUTPUT_ICNS"
