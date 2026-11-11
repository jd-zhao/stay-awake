#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
OUTPUT_DIR="${1:-$HOME/Applications}"
APP="$OUTPUT_DIR/Stay Awake.app"
if [[ -e "$APP" ]]; then
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
    if [[ "$BUNDLE_ID" != "local.stayawake.app" ]]; then
        echo "Refusing to overwrite an unrelated app: $APP" >&2
        exit 1
    fi
    if pgrep -f "^${APP}/Contents/MacOS/StayAwake( |$)" >/dev/null; then
        echo "Quit Stay Awake before replacing the installed app." >&2
        exit 1
    fi
fi
if [[ "${2:-}" == "--universal" ]]; then
    swift build -c release --build-system native --triple arm64-apple-macosx14.0 --scratch-path .build/silicon
    swift build -c release --build-system native --triple x86_64-apple-macosx14.0 --scratch-path .build/intel
    ARM_DIR="$(swift build -c release --build-system native --triple arm64-apple-macosx14.0 --scratch-path .build/silicon --show-bin-path)"
    INTEL_DIR="$(swift build -c release --build-system native --triple x86_64-apple-macosx14.0 --scratch-path .build/intel --show-bin-path)"
    mkdir -p .build/universal
    xcrun lipo -create "$ARM_DIR/StayAwake" "$INTEL_DIR/StayAwake" -output .build/universal/StayAwake
    BINARY="$PWD/.build/universal/StayAwake"
else
    swift build -c release --build-system native --scratch-path .build/native-host
    BIN_DIR="$(swift build -c release --build-system native --scratch-path .build/native-host --show-bin-path)"
    BINARY="$BIN_DIR/StayAwake"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/StayAwake"
xcrun strip -S "$APP/Contents/MacOS/StayAwake"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
swift scripts/icon.swift "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p dist
ditto -c -k --norsrc --keepParent "$APP" "$PWD/dist/Stay-Awake.zip"
echo "Built: $APP"
