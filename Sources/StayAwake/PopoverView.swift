import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var session: AwakeSession
    @ObservedObject var preferences: Preferences
    @Environment(\.colorScheme) private var scheme
    @State private var page: Page = .home
    @State private var editorKind: TimerEditorKind = .duration
    enum Page { case home, timer, settings }
    private var p: Palette { Palette(scheme) }

    init(session: AwakeSession, preferences: Preferences, initialPage: Page = .home, initialEditor: TimerEditorKind = .duration) {
        self.session = session
        self.preferences = preferences
        _page = State(initialValue: initialPage)
        _editorKind = State(initialValue: initialEditor)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.top, 10).padding(.bottom, 12)
            Group {
                switch page {
                case .home: home
                case .timer: CustomTimerView(session: session, initialKind: editorKind) { page = .home }
                case .settings: settings
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16).frame(width: UtilityLayout.width, height: UtilityLayout.height)
        .background(p.background).foregroundStyle(p.foreground)
        .font(.system(size: 12)).tint(p.foreground)
    }

    private var header: some View {
        HStack(spacing: 7) {
            if page != .home {
                SmallIconButton(symbol: "chevron.left", label: "Back") { page = .home }
            } else {
                Image(systemName: "sun.max").font(.system(size: 13))
            }
            Text(page == .home ? "Stay Awake" : page == .timer ? "Custom timer" : "Settings")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if page == .home {
                SmallIconButton(symbol: "gearshape", label: "Settings") {
                    preferences.refreshLoginStatus()
                    page = .settings
                }.keyboardShortcut(",", modifiers: .command)
            }
        }.frame(height: 24)
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.isActive ? (session.deadline == nil ? "Awake" : session.remaining) : "Not running")
                    .font(.system(size: 20, weight: .medium)).monospacedDigit()
                Text(statusDetail).font(.system(size: 11)).foregroundStyle(p.secondary)
            }.frame(height: 36, alignment: .leading)
            VStack(spacing: 10) {
                FormRow(title: "Mode") {
                    PopUpField(label: "Mode", value: session.mode, options: [(.display, "Screen and Mac"), (.system, "Mac only")]) { session.select(mode: $0) }
                }
                FormRow(title: "Timer") {
                    PopUpField(label: "Timer", value: session.duration, options: [
                        (.forever, "Until stopped"), (.halfHour, "30 minutes"), (.hour, "1 hour"), (.twoHours, "2 hours"),
                        (.custom, session.duration == .custom ? session.durationTitle + "…" : "Custom duration…"),
                        (.untilTime, session.duration == .untilTime ? session.durationTitle + "…" : "Until a time…")
                    ], select: chooseTimer)
                }
                if session.duration == .custom || session.duration == .untilTime {
                    HStack {
                        Spacer()
                        Button("Edit timer…") { openEditor(session.duration == .untilTime ? .endTime : .duration) }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            Text(session.errorMessage ?? (session.mode == .display ? "Screen stays on. Mac stays awake." : "Mac stays awake. The screen can turn off."))
                .font(.system(size: 11)).foregroundStyle(p.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .topLeading)
                .help(session.errorMessage ?? "Manual lock and lid close still work.")
            Spacer(minLength: 0)
            Button { session.toggle() } label: {
                Text(session.isActive ? "Stop" : "Start").frame(maxWidth: .infinity)
            }.buttonStyle(UtilityButtonStyle()).keyboardShortcut(.defaultAction)
        }
    }

    private var statusDetail: String {
        if !session.isActive { return "Choose a timer, then start." }
        if session.isScreenProtectionPaused { return "Screen protection paused while locked." }
        if let deadline = session.deadline { return "Ends at " + deadline.formatted(date: .omitted, time: .shortened) }
        return "Until you stop the session."
    }

    private func chooseTimer(_ choice: SessionDuration) {
        switch choice {
        case .custom: openEditor(.duration)
        case .untilTime: openEditor(.endTime)
        default: session.select(duration: choice)
        }
    }

    private func openEditor(_ kind: TimerEditorKind) {
        editorKind = kind
        page = .timer
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormRow(title: "Appearance") {
                PopUpField(label: "Appearance", value: preferences.appearance, options: AppAppearance.allCases.map { ($0, $0.title) }) { preferences.appearance = $0 }
            }
            Divider()
            Toggle("Show time remaining in menu bar", isOn: $preferences.showCountdown)
                .toggleStyle(.checkbox).controlSize(.regular)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Open at login", isOn: Binding(get: { preferences.startsAtLogin }, set: { preferences.setStartsAtLogin($0) }))
                    .toggleStyle(.checkbox).controlSize(.regular)
                Text("Opens without starting a session.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 19)
                if preferences.loginStatus == .requiresApproval {
                    Button("Allow in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                        .buttonStyle(.plain).font(.system(size: 11))
                }
                if let error = preferences.loginError { Text(error).font(.system(size: 11)).lineLimit(2) }
            }
            Spacer(minLength: 0)
            Divider()
            HStack {
                Button("About") { NSApp.orderFrontStandardAboutPanel() }.buttonStyle(.plain)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).keyboardShortcut("q", modifiers: .command)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
