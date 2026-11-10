#!/bin/bash
# Builds "Scrcpy Launcher.app". Pass "install" to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Scrcpy Launcher.app"
mkdir -p build
if [ ! -f build/AppIcon.icns ]; then
  swift make_icon.swift build/icon.png
  rm -rf build/AppIcon.iconset; mkdir build/AppIcon.iconset
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -parse-as-library -O -swift-version 5 -target arm64-apple-macos14.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/ScrcpyLauncher"
cp Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP"
echo "Built $APP"
if [ "${1:-}" = "install" ]; then
  rm -rf "/Applications/Scrcpy Launcher.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Scrcpy Launcher.app"
fi
