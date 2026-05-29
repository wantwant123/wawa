#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/FileFrogNative.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$BUILD_DIR/FileFrogNative.app.zip"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp ".build/release/FileFrogNative" "$MACOS_DIR/FileFrogNative"
chmod +x "$MACOS_DIR/FileFrogNative"
cp "Sources/FileFrogNative/Info.plist" "$CONTENTS_DIR/Info.plist"

cd "$BUILD_DIR"
/usr/bin/zip -qr "FileFrogNative.app.zip" "FileFrogNative.app"

echo "Packaged: $BUILD_DIR/FileFrogNative.app.zip"
