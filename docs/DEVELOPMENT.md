# Development and releases

Stay Awake is a Swift Package executable wrapped in a macOS app bundle. Runtime dependencies are Apple frameworks only: SwiftUI, AppKit, IOKit, Combine and ServiceManagement.

## Layout

- `Sources/StayAwake/Session.swift`: wake-session lifecycle, assertions, deadlines and persisted timing choices.
- `PopoverView.swift`, `CustomTimerView.swift`, `Design.swift`: compact menu bar interface.
- `NativePopUp.swift`, `NativeTimePicker.swift`: AppKit controls with explicit sizing.
- `Preferences.swift`: appearance, countdown and optional login registration.
- `Resources/`: bundle metadata and privacy manifest.
- `scripts/`: build, package, notarize and generate documentation images.

## Build and check

```sh
zsh scripts/build.sh /tmp/stayawake-build --universal
'/tmp/stayawake-build/Stay Awake.app/Contents/MacOS/StayAwake' --self-check --wait-for-heartbeat
zsh scripts/package.sh '/tmp/stayawake-build/Stay Awake.app'
```

The normal build produces an ad-hoc-signed app with Hardened Runtime. It strips debugging symbols before signing and includes the MIT license in the bundle. It does not submit anything to Apple or GitHub.

The self-check uses a temporary UserDefaults suite. Lock/unlock behavior is exercised through an injected console-state reader; this is not a substitute for a real unattended idle-lock test. Test actual login registration on a correctly installed, signed app. Intel binaries are cross-compiled and need a physical Intel installation check.

`--resume-until UNIX_TIMESTAMP` is a local update aid for restoring an existing timed session. Normal app launches always enter standby.

## Documentation images

```sh
zsh scripts/screenshots.sh
```

This compiles a separate offscreen renderer from the application's actual SwiftUI and AppKit view sources. It renders representative idle, duration, and end-time views into `docs/images/`, using an isolated preference suite. It does not change the installed app's preferences or begin a wake session. These images show app content without window shadows or a menu bar backdrop.

## Signed and notarized direct distribution

A Developer ID Application certificate and a configured notarytool Keychain profile are required. Credentials must not be committed to the repository.

```sh
STAYAWAKE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
STAYAWAKE_NOTARY_PROFILE='your-keychain-profile' \
zsh scripts/release.sh
```

The script builds the universal app, signs with Hardened Runtime and a timestamp, submits it to Apple, checks for `Accepted`, staples the app, verifies Gatekeeper assessment, creates/signs/notarizes/staples the DMG, then updates the ZIP and checksum. It stops if signing or notarization fails. Running `build.sh` or GitHub Actions does not perform this notarization workflow.

The bundle ID remains `local.stayawake.app` for compatibility with existing local preferences. It should be reviewed before a future separately branded or App Store release. The current GitHub download is explicitly a preview; neither Mac App Store approval nor Apple notarization is claimed.

References: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [user-activity assertion](https://developer.apple.com/documentation/iokit/1557127-iopmassertiondeclareuseractivity), [NSDatePicker](https://developer.apple.com/documentation/appkit/nsdatepicker).
