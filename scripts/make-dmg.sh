#!/bin/bash
# Builds a universal (Apple Silicon + Intel) release build, assembles the
# .app, and packages it into an installable DMG.
# Usage: scripts/make-dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-0.2.0}"
APP="GalleryCast.app"
DMG="dist/GalleryCast-v${VERSION}-universal.dmg"

echo "Assembling universal release bundle..."
./scripts/build-app.sh release universal

echo "Verifying architectures..."
ARCHS="$(lipo -archs ".build/release/GalleryCast")"
echo "Architectures: $ARCHS"
if [[ "$ARCHS" != *"arm64"* || "$ARCHS" != *"x86_64"* ]]; then
    echo "error: expected a universal arm64 + x86_64 binary" >&2
    exit 1
fi

echo "Creating DMG..."
rm -rf dist/staging "$DMG"
mkdir -p dist/staging
cp -R "$APP" dist/staging/
ln -s /Applications dist/staging/Applications
hdiutil create -volname "Gallery Cast" -srcfolder dist/staging -ov -format UDZO "$DMG"
rm -rf dist/staging

echo "Verifying DMG..."
hdiutil verify "$DMG"

echo "Done: $DMG"
