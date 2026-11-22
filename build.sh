#!/bin/zsh
# Builds Revisor.app (release) and signs it.
#
#   ./build.sh                 build + sign
#   ./build.sh --install       also copy to ~/Applications and open it
#
# Signing: uses your first "Apple Development" certificate if you have one, so
# the Accessibility permission survives rebuilds. Without one it signs ad hoc
# (works, but macOS may ask for the permission again after each rebuild).
#
# Overrides (env vars or a git-ignored local.env file next to this script):
#   REVISOR_SIGN_ID    codesign identity (name or SHA-1), "-" for ad hoc
#   REVISOR_BUNDLE_ID  bundle identifier (default: app.revisor.Revisor)
set -euo pipefail
cd "$(dirname "$0")"
[[ -f local.env ]] && source local.env

VERSION=$(cat VERSION 2>/dev/null || echo "0.1.0")
BUNDLE_ID=${REVISOR_BUNDLE_ID:-app.revisor.Revisor}

swift build -c release --product Revisor 2>&1 | grep -vE '^\[' || true
BIN=.build/release/Revisor
[[ -x $BIN ]] || { echo "build failed"; exit 1; }

APP=Revisor.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp $BIN $APP/Contents/MacOS/Revisor
[[ -f Assets/AppIcon.icns ]] && cp Assets/AppIcon.icns $APP/Contents/Resources/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleName</key><string>Revisor</string>
  <key>CFBundleDisplayName</key><string>Revisor</string>
  <key>CFBundleExecutable</key><string>Revisor</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST

SIGN_ID=${REVISOR_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 'Apple Development' | awk '{print $2}' || true)}
codesign --force --sign "${SIGN_ID:--}" $APP
echo "Built $(pwd)/$APP  (bundle ${BUNDLE_ID}, signed with ${SIGN_ID:-ad hoc})"

if [[ ${1:-} == "--install" ]]; then
  pkill -x Revisor 2>/dev/null || true
  rm -rf ~/Applications/Revisor.app
  mkdir -p ~/Applications
  cp -R $APP ~/Applications/
  open ~/Applications/Revisor.app
  echo "Installed to ~/Applications/Revisor.app"
fi
