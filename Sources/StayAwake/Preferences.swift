import AppKit
import Combine
import ServiceManagement
import SwiftUI

@MainActor
enum AppDefaults {
    static let store = UserDefaults.standard
}

enum AppAppearance: String, CaseIterable {
    case system, light, dark
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var isPopoverVisible = false
    @Published var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "appearance")
            NSApp.appearance = appearance.nsAppearance
            for window in NSApp.windows { window.appearance = appearance.nsAppearance }
        }
    }
    @Published var showCountdown: Bool { didSet { defaults.set(showCountdown, forKey: "showCountdown") } }
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published var loginError: String?

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? AppDefaults.store
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: "appearance") ?? "system") ?? .system
        showCountdown = defaults.object(forKey: "showCountdown") as? Bool ?? true
    }

    var startsAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }

    func setStartsAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        refreshLoginStatus()
    }
}
