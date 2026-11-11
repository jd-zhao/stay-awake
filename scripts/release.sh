#!/bin/zsh
# Direct-distribution release. Credentials stay in the macOS Keychain.
set -euo pipefail
cd "${0:A:h:h}"
: "${STAYAWAKE_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
: "${STAYAWAKE_NOTARY_PROFILE:?Set the name of an existing notarytool Keychain profile}"
if [[ "$STAYAWAKE_SIGN_IDENTITY" != 'Developer ID Application:'* ]]; then
    echo 'A Developer ID Application identity is required for public distribution.' >&2
    exit 1
fi
security find-identity -v -p codesigning | /usr/bin/grep -F -- "$STAYAWAKE_SIGN_IDENTITY" >/dev/null
RELEASE_ROOT=$(mktemp -d /tmp/stayawake-release.XXXXXX)
zsh scripts/build.sh "$RELEASE_ROOT" --universal
APP="$RELEASE_ROOT/Stay Awake.app"
codesign --force --options runtime --timestamp --sign "$STAYAWAKE_SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
NOTARY_ZIP="$RELEASE_ROOT/Stay-Awake-notary.zip"
ditto -c -k --norsrc --keepParent "$APP" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$STAYAWAKE_NOTARY_PROFILE" --wait --output-format json > "$RELEASE_ROOT/app-notarization.json"
python3 - "$RELEASE_ROOT/app-notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('App notarization was not accepted. Inspect ' + sys.argv[1])
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
zsh scripts/package.sh "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$PWD/dist/Stay-Awake-${VERSION}.dmg"
codesign --force --timestamp --sign "$STAYAWAKE_SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$STAYAWAKE_NOTARY_PROFILE" --wait --output-format json > "$RELEASE_ROOT/dmg-notarization.json"
python3 - "$RELEASE_ROOT/dmg-notarization.json" <<'PY'
import json, sys
if json.load(open(sys.argv[1])).get('status') != 'Accepted':
    raise SystemExit('DMG notarization was not accepted. Inspect ' + sys.argv[1])
PY
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
ditto -c -k --norsrc --keepParent "$APP" "$PWD/dist/Stay-Awake.zip"
(cd dist && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")
echo "Notarized release ready: $DMG"
