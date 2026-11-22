#!/bin/zsh
# Prints the CHANGELOG section for a version (default: VERSION file).
set -euo pipefail
cd "$(dirname "$0")/.."
V=${1:-$(cat VERSION)}
awk -v v="## ${V}" '$0==v {on=1; next} /^## / && on {exit} on' CHANGELOG.md
