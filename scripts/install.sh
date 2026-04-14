#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/VoiceToText"
APP_NAME="VoiceToText.app"
BUILD_PRODUCT="$PROJECT_DIR/build/Build/Products/Release/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"

cd "$PROJECT_DIR"

echo "→ killing any running instance"
pkill -9 VoiceToText 2>/dev/null || true
sleep 1

echo "→ building Release"
SIGN_ID="${VOICE_TO_TEXT_SIGN_ID:-Developer ID Application: Gurgen Abagyan (N7S7ZCZ5P7)}"
xcodebuild \
    -project VoiceToText.xcodeproj \
    -scheme VoiceToText \
    -configuration Release \
    -derivedDataPath build \
    clean build \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM=N7S7ZCZ5P7 \
    2>&1 | tail -3

if [ ! -d "$BUILD_PRODUCT" ]; then
    echo "✗ build failed: $BUILD_PRODUCT not found"
    exit 1
fi

echo "→ installing to $INSTALL_PATH"
rm -rf "$INSTALL_PATH"
cp -R "$BUILD_PRODUCT" "$INSTALL_PATH"

echo "→ launching"
open "$INSTALL_PATH"

echo "✓ done"
