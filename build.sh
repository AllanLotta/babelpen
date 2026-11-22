#!/bin/zsh
# Builds Babelpen.app (release) and signs it.
#
#   ./build.sh                 build + sign
#   ./build.sh --install       also copy to ~/Applications and open it
#
# Release builds (CI): BABELPEN_UNIVERSAL=1 builds for Apple Silicon and Intel,
# BABELPEN_HARDENED=1 signs with the hardened runtime (needed for notarization).
#
# Signing: uses your first "Apple Development" certificate if you have one, so
# the Accessibility permission survives rebuilds. Without one it signs ad hoc
# (works, but macOS may ask for the permission again after each rebuild).
#
# Overrides (env vars, or a git-ignored local.env next to this script using
# `: ${VAR:=value}` so command-line values still win):
#   BABELPEN_SIGN_ID    codesign identity (name or SHA-1), "-" for ad hoc
#   BABELPEN_BUNDLE_ID  bundle identifier (default: app.babelpen.Babelpen)
set -euo pipefail
cd "$(dirname "$0")"
[[ -f local.env ]] && source local.env

VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")
BUNDLE_ID=${BABELPEN_BUNDLE_ID:-app.babelpen.Babelpen}

if [[ ${BABELPEN_UNIVERSAL:-0} == 1 ]]; then
  swift build -c release --product Babelpen --arch arm64 --arch x86_64 2>&1 | grep -vE '^\[' || true
  BIN=.build/apple/Products/Release/Babelpen
else
  swift build -c release --product Babelpen 2>&1 | grep -vE '^\[' || true
  BIN=.build/release/Babelpen
fi
[[ -x $BIN ]] || { echo "build failed"; exit 1; }

APP=Babelpen.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN $APP/Contents/MacOS/Babelpen
[[ -f Assets/AppIcon.icns ]] && cp Assets/AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>Babelpen</string>
  <key>CFBundleDisplayName</key><string>Babelpen</string>
  <key>CFBundleExecutable</key><string>Babelpen</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

SIGN_ID=${BABELPEN_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | awk '{print $2}' || true)}
SIGN_FLAGS=(--force --sign "${SIGN_ID:--}")
[[ ${BABELPEN_HARDENED:-0} == 1 ]] && SIGN_FLAGS+=(--options runtime --timestamp)
codesign "${SIGN_FLAGS[@]}" $APP
echo "Built $(pwd)/$APP  (bundle ${BUNDLE_ID}, signed with ${SIGN_ID:-ad hoc})"

if [[ ${1:-} == "--install" ]]; then
  pkill -x Babelpen 2>/dev/null || true
  rm -rf ~/Applications/Babelpen.app
  mkdir -p ~/Applications
  cp -R $APP ~/Applications/
  open ~/Applications/Babelpen.app
  echo "Installed to ~/Applications/Babelpen.app"
fi
