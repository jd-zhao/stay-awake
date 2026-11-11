#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="${1:?Pass the built Stay Awake.app path}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGING=$(mktemp -d /tmp/stayawake-dmg.XXXXXX)
ditto --norsrc "$APP" "$STAGING/Stay Awake.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p dist
DMG="$PWD/dist/Stay-Awake-${VERSION}.dmg"
hdiutil create -volname 'Stay Awake' -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
echo "Packaged: $DMG"
