#!/bin/bash
# Babelpen installer: downloads the latest release and installs it.
#
#   curl -fsSL https://raw.githubusercontent.com/AllanLotta/babelpen/main/install.sh | bash
#
# Releases are not notarized yet, so this clears the download quarantine flag
# for Babelpen.app only. Read this script before running it, it's short.
set -euo pipefail

REPO="AllanLotta/babelpen"
APP="Babelpen.app"

[[ "$(uname)" == "Darwin" ]] || { echo "Babelpen runs on macOS only."; exit 1; }

DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

echo "→ Finding the latest Babelpen release…"
URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed -E 's/.*"(https[^"]+)"/\1/')
[[ -n "$URL" ]] || { echo "Couldn't find a release to download."; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "→ Downloading ${URL##*/}…"
curl -fL --progress-bar "$URL" -o "$TMP/babelpen.zip"
ditto -x -k "$TMP/babelpen.zip" "$TMP"

pkill -x Babelpen 2>/dev/null || true
rm -rf "${DEST:?}/${APP}"
ditto "$TMP/${APP}" "${DEST}/${APP}"
xattr -dr com.apple.quarantine "${DEST}/${APP}" 2>/dev/null || true

echo "✓ Installed to ${DEST}/${APP}"
if ! command -v claude >/dev/null 2>&1 && ! command -v codex >/dev/null 2>&1; then
  echo "! No AI CLI found. Install Claude Code (https://docs.claude.com/en/docs/claude-code)"
  echo "  or Codex (https://github.com/openai/codex) and log in once."
fi
echo "→ Opening Babelpen. Allow Accessibility access when macOS asks, then look for ✎ in the menu bar."
open "${DEST}/${APP}"
