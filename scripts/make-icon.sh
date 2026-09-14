#!/bin/bash
# Resources/AppIcon.icns を作り直す（アイコンの見た目を変えたときだけ実行すればよい）
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$TMP"
BIN="$(mktemp -d)/make-icon"
swiftc -O scripts/make-icon.swift -o "$BIN"
"$BIN" "$TMP"
iconutil -c icns "$TMP" -o Resources/AppIcon.icns
echo "built: Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
