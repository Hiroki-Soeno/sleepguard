#!/bin/bash
# SleepGuard を .app にビルドする。--install で /Applications に入れて起動する。
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
APP="$ROOT/build/SleepGuard.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# ビルド中間物をSpotlight/Launchpadに拾わせない（拾われると同じアプリが2つ並ぶ）
touch "$ROOT/build/.metadata_never_index"

# Intel Macでも動くように universal（arm64 + x86_64）で作る
OBJ="$(mktemp -d)"
for ARCH in arm64 x86_64; do
  swiftc -O -target "${ARCH}-apple-macos13.0" \
    -framework Cocoa -framework IOKit -framework ServiceManagement \
    -o "$OBJ/SleepGuard-$ARCH" \
    Sources/main.swift
done
lipo -create "$OBJ/SleepGuard-arm64" "$OBJ/SleepGuard-x86_64" -output "$APP/Contents/MacOS/SleepGuard"
rm -rf "$OBJ"

cp scripts/install-sudoers.sh "$APP/Contents/Resources/install-sudoers.sh"
cp scripts/uninstall-sudoers.sh "$APP/Contents/Resources/uninstall-sudoers.sh"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SleepGuard</string>
  <key>CFBundleDisplayName</key><string>SleepGuard</string>
  <key>CFBundleExecutable</key><string>SleepGuard</string>
  <key>CFBundleIdentifier</key><string>jp.soeno.sleepguard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# CODESIGN_IDENTITY を渡せば Developer ID で署名する（未指定なら ad-hoc）
IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - --identifier jp.soeno.sleepguard "$APP"
else
  # 公証に出すには Hardened Runtime（--options runtime）が要る
  codesign --force --timestamp --options runtime \
    --sign "$IDENTITY" --identifier jp.soeno.sleepguard "$APP"
fi
echo "built: $APP ($(lipo -archs "$APP/Contents/MacOS/SleepGuard"), signed by: $IDENTITY)"

if [ "${1:-}" = "--install" ]; then
  DEST="/Applications/SleepGuard.app"
  osascript -e 'quit app "SleepGuard"' >/dev/null 2>&1 || true
  pkill -x SleepGuard >/dev/null 2>&1 || true
  sleep 1
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  # 中間物はLaunch Servicesから登録解除して消す（Launchpadの重複防止）
  "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
  rm -rf "$APP"
  echo "installed & launched: $DEST"
fi
