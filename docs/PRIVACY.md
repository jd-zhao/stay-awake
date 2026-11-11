# Privacy

Stay Awake runs locally on your Mac. The app does not make network requests, collect analytics, display advertising, create accounts, or send your information to a server.

Your timer, mode, appearance and menu bar preferences are stored locally using macOS UserDefaults. If you enable Open at login, macOS ServiceManagement manages that registration.

The app reads console lock and active-user state to pause screen protection while your session is locked or switched away. It does not record or transmit this state. During an active Screen and Mac session, it reports user activity to macOS without generating keyboard or mouse events.

It does not request access to your microphone, camera, contacts, documents, screen recording or Accessibility controls. Standard copy/paste actions use the normal macOS text-editing system.

Self-checks and the documentation renderer use separate temporary preference suites, which are removed after completion. Developer release tooling submits the app binary to Apple only when the notarization script is explicitly run. This is not a feature of the installed app.

For questions, open an issue in [jd-zhao/stay-awake](https://github.com/jd-zhao/stay-awake/issues). Do not include private account information in public issues.
