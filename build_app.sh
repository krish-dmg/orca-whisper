#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Orca Whisper"
BUNDLE_NAME="OrcaWhisper.app"
BUILD_DIR=".build/release"
APP_DIR="$SCRIPT_DIR/$BUNDLE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building release binary with Swift compiler..."
swift build -c release --arch arm64

echo "Assembling $BUNDLE_NAME bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/OrcaWhisper" "$MACOS_DIR/OrcaWhisper"
chmod +x "$MACOS_DIR/OrcaWhisper"

# Copy Info.plist
cp "$SCRIPT_DIR/OrcaWhisper/Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy AppIcon and assets
if [ -f "$SCRIPT_DIR/OrcaWhisper/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/OrcaWhisper/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

if [ -f "$SCRIPT_DIR/OrcaWhisper/menubar_icon.png" ]; then
    cp "$SCRIPT_DIR/OrcaWhisper/menubar_icon.png" "$RESOURCES_DIR/menubar_icon.png"
    cp "$SCRIPT_DIR/OrcaWhisper/menubar_icon@2x.png" "$RESOURCES_DIR/menubar_icon@2x.png"
fi

# Code sign with entitlements
DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F '"' '{print $2}' || true)

if [ -n "$DEV_ID" ]; then
    echo "Signing application bundle with certificate: $DEV_ID"
    codesign --force --deep --sign "$DEV_ID" \
        --entitlements "$SCRIPT_DIR/OrcaWhisper/OrcaWhisper.entitlements" \
        "$APP_DIR"
else
    echo "Signing application bundle with ad-hoc identity..."
    codesign --force --deep --sign - \
        --entitlements "$SCRIPT_DIR/OrcaWhisper/OrcaWhisper.entitlements" \
        "$APP_DIR"
fi

echo "Successfully built $APP_DIR"
