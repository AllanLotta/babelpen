#!/bin/zsh
# Packages Babelpen.app into dist/: a .zip (used by install.sh) and a .dmg.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
[[ -d Babelpen.app ]] || { echo "run ./build.sh first"; exit 1; }

rm -rf dist && mkdir -p dist
ZIP="dist/Babelpen-${VERSION}.zip"
DMG="dist/Babelpen-${VERSION}.dmg"

ditto -c -k --sequesterRsrc --keepParent Babelpen.app "$ZIP"

STAGE=$(mktemp -d)
ditto Babelpen.app "$STAGE/Babelpen.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Babelpen ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

(cd dist && shasum -a 256 *.zip *.dmg > SHA256SUMS.txt)
ls -la dist
