#!/bin/bash
# Builds GalleryCast and wraps the binary in a proper macOS app bundle.
# Usage: scripts/build-app.sh          (debug)
#        scripts/build-app.sh release  (optimized)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-debug}"
APP="GalleryCast.app"

echo "Building ($CONFIGURATION)..."
swift build -c "$CONFIGURATION"

BIN=".build/$CONFIGURATION/GalleryCast"

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GalleryCast"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Gallery Cast</string>
    <key>CFBundleDisplayName</key>
    <string>Gallery Cast</string>
    <key>CFBundleIdentifier</key>
    <string>com.aniketpathak.gallerycast</string>
    <key>CFBundleExecutable</key>
    <string>GalleryCast</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.photography</string>
</dict>
</plist>
PLIST

echo "Done: $APP (double-click to launch, or: open $APP)"
