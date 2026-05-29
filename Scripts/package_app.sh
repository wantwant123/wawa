#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/File Frog.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DMG_PATH="$BUILD_DIR/FileFrog.dmg"
DMG_RW_PATH="$BUILD_DIR/FileFrog-rw.dmg"
DMG_MOUNT="$BUILD_DIR/dmg-mount"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR" "$DMG_MOUNT" "$BUILD_DIR/File Frog.app.zip" "$BUILD_DIR/FileFrogNative.app" "$BUILD_DIR/FileFrogNative.app.zip" "$DMG_PATH" "$DMG_RW_PATH" "$BUILD_DIR/FileFrogNative.dmg"
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
  -size 80m \
  -fs HFS+ \
  -ov \
  "$DMG_RW_PATH"

mkdir -p "$DMG_MOUNT"
/usr/bin/hdiutil attach "$DMG_RW_PATH" -nobrowse -mountpoint "$DMG_MOUNT"
/usr/bin/ditto "File Frog.app" "$DMG_MOUNT/File Frog.app"
ln -s /Applications "$DMG_MOUNT/Applications"

/usr/bin/osascript <<APPLESCRIPT || true
tell application "Finder"
  tell disk "File Frog"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {180, 140, 720, 520}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background color of viewOptions to {65535, 65535, 65535}
    set position of item "File Frog.app" of container window to {170, 185}
    set position of item "Applications" of container window to {395, 185}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

sync
/usr/bin/hdiutil detach "$DMG_MOUNT"
/usr/bin/hdiutil convert "$DMG_RW_PATH" \
  -format UDZO \
  -o "$DMG_PATH"
rm -rf "$DMG_MOUNT" "$DMG_RW_PATH"

echo "Packaged: $DMG_PATH"
