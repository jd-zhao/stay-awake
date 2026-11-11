#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
DOCS_STAGE=$(mktemp -d /tmp/stayawake-screenshots.XXXXXX)
DOCS_APP="$DOCS_STAGE/Screenshots.app"
mkdir -p "$DOCS_APP/Contents/MacOS"
python3 - "$DOCS_APP/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({'CFBundleIdentifier':'local.stayawake.screenshots', 'CFBundleExecutable':'Screenshots',
                  'CFBundlePackageType':'APPL','LSUIElement':True}, f)
PY
typeset -a SOURCES
for file in Sources/StayAwake/*.swift; do
    if [[ "${file:t}" != "App.swift" ]]; then SOURCES+=("$file"); fi
done
xcrun swiftc -O -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    "${SOURCES[@]}" scripts/RenderScreenshots.swift -o "$DOCS_APP/Contents/MacOS/Screenshots"
codesign --force --sign - "$DOCS_APP"
"$DOCS_APP/Contents/MacOS/Screenshots" "$PWD/docs/images"
