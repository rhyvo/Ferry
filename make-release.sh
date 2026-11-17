#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
FERRY_RELEASE=1 ./build.sh --no-install
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
STAGE="build/dmg"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto build/Ferry.app "$STAGE/Ferry.app"
ln -s /Applications "$STAGE/Applications"
DMG="build/Ferry-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Ferry $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Done: $(pwd)/$DMG"
