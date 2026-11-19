#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Swift isn't set up. Run:  xcode-select --install   (or open Xcode once), then try again."
  exit 1
fi

APP="build/Ferry.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
xcrun swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macos14.0 \
  -framework SwiftUI -framework AppKit -framework GameController \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Ferry"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/ferry-winbuttons.exe "$APP/Contents/Resources/"
cp Resources/d3d12-hide-rov.dll "$APP/Contents/Resources/"
cp Resources/d3d9-ferry-x86.dll Resources/d3d9-ferry-x64.dll "$APP/Contents/Resources/"
cp Resources/dxgi-vsync-x86.dll Resources/dxgi-vsync-x64.dll "$APP/Contents/Resources/"
cp Resources/xinput-remap-x86.dll Resources/xinput-remap-x64.dll "$APP/Contents/Resources/"
cp Resources/ferry-padkeys.exe "$APP/Contents/Resources/"
cp Resources/ferry-vk-layer.json Resources/libferry_vk_layer.dylib "$APP/Contents/Resources/"

echo "Making the icon…"
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

IDENTITY="Ferry Local Signing"
if [[ "${FERRY_RELEASE:-}" == "1" ]]; then
  echo "Signing (ad-hoc, for release)…"
  strip -x "$APP/Contents/MacOS/Ferry"
  codesign --force --deep --sign - "$APP"
elif security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  echo "Signing with \"$IDENTITY\"…"
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "Signing (ad-hoc, for this Mac; permissions will be asked again after each build)…"
  codesign --force --deep --sign - "$APP"
fi

ferry_busy() {
  pgrep -x Ferry >/dev/null || return 1
  local data="$HOME/Library/Application Support/Ferry"
  compgen -G "$data/Cache/*.part" >/dev/null || compgen -G "$data/Runtimes/*.new" >/dev/null \
    || compgen -G "$data/Runtimes/*.building" >/dev/null || compgen -G "$data/Templates/*.building" >/dev/null \
    || pgrep -f wineserver >/dev/null || pgrep -f "Ferry/Runtimes/7zip/7zz" >/dev/null
}

if [[ "${1:-}" != "--no-install" ]] && ferry_busy; then
  echo "Built, but not installed: Ferry is downloading, unpacking, preparing a Windows environment or running a game."
  echo "(Installing quits Ferry, which would cut that off.)"
  echo "Run ./build.sh again once it's done. The new build is in $(pwd)/$APP"
elif [[ "${1:-}" != "--no-install" ]]; then
  osascript -e 'quit app "Ferry"' >/dev/null 2>&1 || true
  sleep 1
  rm -rf /Applications/Ferry.app
  ditto "$APP" /Applications/Ferry.app
  touch /Applications/Ferry.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Ferry.app >/dev/null 2>&1 || true
  echo "Done. Ferry is in /Applications."
  open /Applications/Ferry.app
else
  echo "Done. Ferry is in $(pwd)/$APP"
fi
