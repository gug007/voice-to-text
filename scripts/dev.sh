#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$REPO_ROOT/VoiceToText"
BUILD_PRODUCT="$PROJECT_DIR/build-dev/Build/Products/Debug/VoiceToText.app"
INSTALL_PATH="/Applications/VoiceToText-Dev.app"
DEV_BUNDLE_ID="voice-to-text-ai.VoiceToText.dev"

cd "$PROJECT_DIR"

echo "→ killing any running dev instance"
pkill -9 -f "VoiceToText-Dev" 2>/dev/null || true
sleep 1

echo "→ building Debug ($DEV_BUNDLE_ID)"
LOCAL_SIGN_ID="VoiceToText Local Signer"
EXPLICIT_SIGN_ID="${VOICE_TO_TEXT_SIGN_ID:-${SIGN_ID:-}}"
if [ -n "$EXPLICIT_SIGN_ID" ]; then
    SIGN_ID="$EXPLICIT_SIGN_ID"
else
    "$SCRIPT_DIR/create-signing-cert.sh"
    SIGN_ID="$LOCAL_SIGN_ID"
fi

TEAM_ARGS=()
if [[ "$SIGN_ID" == Developer\ ID\ Application:* || "$SIGN_ID" == Apple\ Development:* ]]; then
    TEAM_ARGS=(DEVELOPMENT_TEAM=N7S7ZCZ5P7)
fi

xcodebuild \
    -project VoiceToText.xcodeproj \
    -scheme VoiceToText \
    -configuration Debug \
    -derivedDataPath build-dev \
    build \
    PRODUCT_BUNDLE_IDENTIFIER="$DEV_BUNDLE_ID" \
    INFOPLIST_KEY_CFBundleDisplayName="VoiceToText-Dev" \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_STYLE=Manual \
    "${TEAM_ARGS[@]}" \
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

echo "✓ done — grant Accessibility + Input Monitoring to VoiceToText-Dev once; future runs keep the permissions."
