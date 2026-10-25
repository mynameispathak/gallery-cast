#!/bin/bash
# Builds GalleryCast and wraps the binary in a proper macOS app bundle.
# Usage: scripts/build-app.sh          (debug)
#        scripts/build-app.sh release  (optimized)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${1:-debug}"
UNIVERSAL="${2:-}"
APP="GalleryCast.app"

echo "Building ($CONFIGURATION)..."
if [ "$UNIVERSAL" = "universal" ]; then
    swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
else
    swift build -c "$CONFIGURATION"
fi

BIN=".build/$CONFIGURATION/GalleryCast"

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GalleryCast"
if [ -f assets/AppIcon.icns ]; then
    cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

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
    <string>0.2.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.photography</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Gallery Cast finds Cast devices (Android TV, Chromecast) on your Wi-Fi so you can display your photos on them.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_googlecast._tcp</string>
    </array>
</dict>
</plist>
PLIST

echo "Done: $APP (double-click to launch, or: open $APP)"
