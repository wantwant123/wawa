#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/FileFrogNative.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$BUILD_DIR/FileFrogNative.dmg"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$BUILD_DIR/FileFrogNative.app.zip" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

"$ROOT_DIR/Scripts/generate_icon.py" "$BUILD_DIR/AppIcon.icns"

cp ".build/release/FileFrogNative" "$MACOS_DIR/FileFrogNative"
chmod +x "$MACOS_DIR/FileFrogNative"
cp "Sources/FileFrogNative/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

cd "$BUILD_DIR"
/usr/bin/ditto -c -k --keepParent "FileFrogNative.app" "FileFrogNative.app.zip"
/usr/bin/hdiutil create \
  -volname "File Frog Native" \
  -srcfolder "FileFrogNative.app" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Packaged: $DMG_PATH"
