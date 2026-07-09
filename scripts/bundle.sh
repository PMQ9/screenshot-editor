#!/bin/sh
# Builds the SwiftPM executable and assembles dist/Screenshot Editor.app.
# Usage: scripts/bundle.sh [debug|release]
set -eu

cd "$(dirname "$0")/.."
CONFIG=${1:-debug}
APP="dist/Screenshot Editor.app"

swift build -c "$CONFIG"

# A previous live instance would keep a stale hotkey registration.
pkill -x ScreenshotEditor 2>/dev/null || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/ScreenshotEditor" "$APP/Contents/MacOS/"
cp scripts/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
codesign --verify "$APP"
echo "Bundled: $APP"
