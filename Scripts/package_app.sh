#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/File Frog.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$BUILD_DIR/FileFrog.dmg"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$BUILD_DIR/File Frog.app.zip" "$BUILD_DIR/FileFrogNative.app" "$BUILD_DIR/FileFrogNative.app.zip" "$DMG_PATH" "$BUILD_DIR/FileFrogNative.dmg"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

"$ROOT_DIR/Scripts/generate_icon.py" "$BUILD_DIR/AppIcon.icns"

cp ".build/release/FileFrogNative" "$MACOS_DIR/FileFrogNative"
chmod +x "$MACOS_DIR/FileFrogNative"
cp "Sources/FileFrogNative/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"
/usr/bin/sips -g pixelWidth -g pixelHeight "$RESOURCES_DIR/AppIcon.icns" >/dev/null

codesign --force --deep --sign - "$APP_DIR"

cd "$BUILD_DIR"
/usr/bin/ditto -c -k --keepParent "File Frog.app" "File Frog.app.zip"
/usr/bin/hdiutil create \
  -volname "File Frog" \
  -srcfolder "File Frog.app" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Packaged: $DMG_PATH"
