#!/bin/bash
# Builds "iPhone Mirror.app" next to this script and opens it.
set -euo pipefail
cd "$(dirname "$0")"
APP="iPhone Mirror.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/iPhoneMirror" main.swift \
  -framework AppKit -framework AVFoundation -framework CoreMediaIO
[ -f Resources/screen-mask.png ] || { echo "Run ./fetch-bezels.sh first"; exit 1; }
cp Resources/*.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>iPhone Mirror</string>
  <key>CFBundleIdentifier</key><string>studio.persimmons.iphone-mirror</string>
  <key>CFBundleExecutable</key><string>iPhoneMirror</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCameraUsageDescription</key><string>Shows your iPhone's screen over USB.</string>
</dict></plist>
PLIST
xattr -cr "$APP"; codesign --force --sign - "$APP"
echo "built $PWD/$APP"
