#!/bin/bash
# Regenerates Resources/AppIcon.icns from tools/make-icon.swift.
# Only needed when changing the artwork; the .icns is committed.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/AppIcon.iconset"

swiftc -O tools/make-icon.swift -o "$WORK/make-icon"
"$WORK/make-icon" "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns

echo "Wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
