import AppKit
import SwiftUI

@main
struct RenderScreenshots {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let suiteName = "local.stayawake.screenshots." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let session = AwakeSession(defaults: defaults, consoleIsUnlocked: { true })
        session.select(duration: .halfHour)
        let preferences = Preferences(defaults: defaults)
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            try render(session, preferences, page: .home, editor: .duration,
                to: output.appendingPathComponent("main-\(appearance.rawValue).png"))
        }
        preferences.appearance = .light
        try render(session, preferences, page: .timer, editor: .endTime,
            to: output.appendingPathComponent("end-time.png"))
        try render(session, preferences, page: .timer, editor: .duration,
            to: output.appendingPathComponent("duration.png"))
        print("Rendered application views to \(output.path)")
    }

    @MainActor private static func render(_ session: AwakeSession, _ preferences: Preferences,
        page: PopoverView.Page, editor: TimerEditorKind, to path: URL) throws {
        let size = NSSize(width: UtilityLayout.width, height: UtilityLayout.height)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = preferences.appearance.nsAppearance
        let host = NSHostingController(rootView: PopoverView(session: session, preferences: preferences,
            initialPage: page, initialEditor: editor))
        host.sizingOptions = []
        host.view.appearance = preferences.appearance.nsAppearance
        host.view.setFrameSize(size)
        window.contentViewController = host
        window.setContentSize(size)
        host.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.displayIfNeeded()
        host.view.layoutSubtreeIfNeeded()
        guard let bitmap = host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds) else {
            throw NSError(domain: "Screenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create a bitmap"])
        }
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Screenshots", code: 2)
        }
        try png.write(to: path, options: .atomic)
        window.close()
    }
}
