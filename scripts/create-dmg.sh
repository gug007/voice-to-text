#!/usr/bin/env bash
set -euo pipefail

# Wrap a built .app bundle in a .dmg with a drag-to-Applications symlink.
#
# Usage: create-dmg.sh <path/to/App.app> <output.dmg>

if [ $# -ne 2 ]; then
    echo "usage: $0 <App.app> <output.dmg>"
    exit 2
fi

APP_PATH="$1"
DMG_PATH="$2"

if [ ! -d "$APP_PATH" ]; then
    echo "✗ $APP_PATH not found"
    exit 1
fi

APP_NAME=$(basename "$APP_PATH")
VOL_NAME=$(basename "$APP_NAME" .app)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

STAGING="$TMP_DIR/dmg-contents"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

echo "✓ created $DMG_PATH"
