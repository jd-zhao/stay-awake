import AppKit
import Combine
import IOKit.pwr_mgt
import SwiftUI

@MainActor
private final class CheckConsole {
    var unlocked = true
}

@main
struct StayAwakeApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-check") {
            runSelfCheck()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func runSelfCheck() {
        let suite = "local.stayawake.selfcheck." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let console = CheckConsole()
        let session = AwakeSession(defaults: defaults, consoleIsUnlocked: { console.unlocked })
        func check(_ condition: Bool, _ message: String) {
            guard condition else { session.stop(); fputs("FAIL: \(message)\n", stderr); exit(1) }
            print("PASS: \(message)")
        }
        session.select(mode: .display)
        session.select(duration: .forever)
        session.start()
        check(session.isActive && session.deadline == nil, "indefinite session starts")
        check(session.verifiedAssertionTypes() == Set(AwakeMode.display.assertionTypes + ["UserIsActive"]), "macOS confirms display, system and user activity assertions")
        let firstHeartbeat = session.lastUserActivityAt
        if CommandLine.arguments.contains("--wait-for-heartbeat") {
            RunLoop.main.run(until: Date().addingTimeInterval(16.5))
            check(session.lastUserActivityAt != firstHeartbeat && session.verifiedAssertionTypes().contains("UserIsActive"), "real timer renews user activity after 15 seconds")
        }
        let displayIDs = session.assertionIDs + [session.userActivityID]
        session.select(mode: .system)
        check(session.verifiedAssertionTypes() == Set(AwakeMode.system.assertionTypes), "mode change releases display assertion")
        check(displayIDs.allSatisfy { IOPMAssertionCopyProperties($0) == nil }, "macOS confirms previous assertions were released")
        session.select(mode: .display)
        let beforeLockIDs = session.assertionIDs + [session.userActivityID]
        console.unlocked = false
        session.refresh()
        check(session.isActive && session.isScreenProtectionPaused && session.verifiedAssertionTypes() == Set(AwakeMode.system.assertionTypes), "locked console pauses screen and user activity protection")
        check(beforeLockIDs.allSatisfy { IOPMAssertionCopyProperties($0) == nil }, "lock pause releases display and user activity assertions")
        console.unlocked = true
        session.refresh()
        check(!session.isScreenProtectionPaused && session.verifiedAssertionTypes().contains("UserIsActive"), "unlock restores idle protection")
        session.select(duration: .halfHour)
        check(session.deadline != nil, "timed session has a deadline")
        let oldDeadline = session.deadline!
        let timedIDs = session.assertionIDs + [session.userActivityID]
        session.refresh(at: oldDeadline.addingTimeInterval(-1))
        check(session.isActive, "session stays active before its deadline")
        session.refresh(at: oldDeadline.addingTimeInterval(1))
        check(!session.isActive && session.verifiedAssertionTypes().isEmpty, "expired session stops")
        check(timedIDs.allSatisfy { IOPMAssertionCopyProperties($0) == nil }, "macOS confirms expiry releases assertions")
        session.start()
        session.select(mode: .display)
        session.select(duration: .forever)
        check(session.deadline == nil && session.verifiedAssertionTypes().count == 3, "timed session can become indefinite")
        let finalIDs = session.assertionIDs + [session.userActivityID]
        session.stop()
        session.stop()
        check(!session.isActive && session.verifiedAssertionTypes().isEmpty, "repeated stop is safe")
        check(finalIDs.allSatisfy { IOPMAssertionCopyProperties($0) == nil }, "macOS confirms stop releases assertions")
        let resumedDeadline = Date().addingTimeInterval(100)
        session.start(resumingUntil: resumedDeadline)
        check(session.deadline == resumedDeadline, "upgrade resume preserves the original deadline")
        session.stop()
        check(session.setCustomDuration(hours: 2, minutes: 15), "custom hours and minutes accepted")
        session.start()
        check(abs(session.deadline!.timeIntervalSince(session.startedAt!) - 8100) < 0.01, "custom duration runs for exactly 2 hours 15 minutes")
        let validDeadline = session.deadline
        check(!session.setCustomDuration(hours: 0, minutes: 0) && !session.setCustomDuration(hours: 1, minutes: 60)
            && !session.setCustomDuration(hours: Int.max, minutes: 0) && session.deadline == validDeadline,
            "invalid custom input cannot replace a running session")
        check(session.setCustomDuration(hours: 168, minutes: 0) && !session.setCustomDuration(hours: 168, minutes: 1), "seven-day boundary enforced")
        let restored = AwakeSession(defaults: defaults, consoleIsUnlocked: { console.unlocked })
        check(restored.duration == .custom && restored.customMinutes == 10080 && !restored.isActive, "custom settings persist without silently starting")
        let until = Date().addingTimeInterval(90)
        check(session.setEndTime(until) && session.deadline == until, "clock end time is exact")
        check(!session.setEndTime(Date().addingTimeInterval(-5)) && session.deadline == until, "past end time is rejected without changing session")
        session.refresh(at: until.addingTimeInterval(1))
        check(!session.isActive && session.verifiedAssertionTypes().isEmpty, "clock-timed session expires and releases protection")
        session.select(duration: .forever)
        session.start()
        check(session.deadline == nil && session.progress == 1, "indefinite selection clears custom deadline")
        session.stop()
        print("All lifecycle checks passed.")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let session = AwakeSession()
    private let preferences = Preferences()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem!
    private var subscription: AnyCancellable?
    private var preferenceSubscription: AnyCancellable?
    private var contextMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = preferences.appearance.nsAppearance
        popover.appearance = preferences.appearance.nsAppearance
        // Reopening the same bundle should use the existing menu bar item.
        let bundleID = Bundle.main.bundleIdentifier ?? "local.stayawake.app"
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        installApplicationMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        contextMenu = NSMenu()
        let toggleItem = NSMenuItem(title: "Keep awake", action: #selector(toggleAwake), keyEquivalent: "")
        toggleItem.target = self
        contextMenu.addItem(toggleItem)
        contextMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Stay Awake", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let hosting = NSHostingController(rootView: PopoverView(session: session, preferences: preferences))
        hosting.sizingOptions = []
        hosting.view.appearance = preferences.appearance.nsAppearance
        hosting.preferredContentSize = NSSize(width: UtilityLayout.width, height: UtilityLayout.height)
        hosting.view.setFrameSize(NSSize(width: UtilityLayout.width, height: UtilityLayout.height))
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: UtilityLayout.width, height: UtilityLayout.height)
        subscription = session.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
        preferenceSubscription = preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.popover.appearance = self.preferences.appearance.nsAppearance
                self.popover.contentViewController?.view.appearance = self.preferences.appearance.nsAppearance
                self.updateStatusItem()
            }
        }
        updateStatusItem()
        if let index = CommandLine.arguments.firstIndex(of: "--resume-until"),
           CommandLine.arguments.indices.contains(index + 1),
           let timestamp = TimeInterval(CommandLine.arguments[index + 1]), timestamp.isFinite {
            session.start(resumingUntil: Date(timeIntervalSince1970: timestamp))
        }
        showPopover()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { session.stop() }

    func popoverWillShow(_ notification: Notification) { preferences.isPopoverVisible = true }
    func popoverDidClose(_ notification: Notification) { preferences.isPopoverVisible = false }

    private func installApplicationMenu() {
        let main = NSMenu()
        let application = NSMenu(title: "Stay Awake")
        let quitItem = NSMenuItem(title: "Quit Stay Awake", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        application.addItem(quitItem)
        let applicationItem = NSMenuItem()
        applicationItem.submenu = application
        main.addItem(applicationItem)

        let edit = NSMenu(title: "Edit")
        func add(_ title: String, _ action: String, _ key: String, modifiers: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: Selector(action), keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            edit.addItem(item)
        }
        add("Undo", "undo:", "z")
        add("Redo", "redo:", "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        add("Cut", "cut:", "x")
        add("Copy", "copy:", "c")
        add("Paste", "paste:", "v")
        add("Select All", "selectAll:", "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: session.isActive ? "sun.max.fill" : "sun.max", accessibilityDescription: "Stay Awake")
        image?.isTemplate = true
        button.image = image
        button.title = preferences.showCountdown ? (session.menuBarTime.map { " \($0)" } ?? "") : ""
        button.toolTip = session.isActive ? "Stay Awake · \(session.isScreenProtectionPaused ? "Screen protection paused while locked" : session.mode.title) · \(session.remaining)" : "Stay Awake · Off"
        button.setAccessibilityLabel(button.toolTip)
        contextMenu.items.first?.title = session.isActive ? "Stop keeping awake" : "Keep awake"
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            statusItem.menu = contextMenu
            sender.performClick(nil)
            statusItem.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @objc private func toggleAwake() { session.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
