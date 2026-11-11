import AppKit
import Combine
import IOKit
import IOKit.pwr_mgt

enum AwakeMode: String, CaseIterable {
    case display, system
    var title: String { self == .display ? "Screen on" : "Mac awake" }
    var subtitle: String {
        self == .display ? "Keep your screen awake and idle protection on." : "Keep tasks running. Screen may lock or sleep."
    }
    var symbol: String { self == .display ? "sun.max" : "desktopcomputer" }
    var assertionTypes: [String] {
        var types = [kIOPMAssertionTypePreventUserIdleSystemSleep as String]
        if self == .display { types.append(kIOPMAssertionTypePreventUserIdleDisplaySleep as String) }
        return types
    }
}

enum SessionDuration: Int, CaseIterable {
    case forever = 0, halfHour = 1800, hour = 3600, twoHours = 7200, custom = -1, untilTime = -2
    static let presets: [Self] = [.forever, .halfHour, .hour, .twoHours]
    var title: String {
        switch self {
        case .forever: "Until I stop"
        case .halfHour: "30 min"
        case .hour: "1 hour"
        case .twoHours: "2 hours"
        case .custom: "Custom"
        case .untilTime: "Until a time"
        }
    }
}

@MainActor
final class AwakeSession: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var mode: AwakeMode = .display
    @Published private(set) var duration: SessionDuration = .forever
    @Published private(set) var deadline: Date?
    @Published private(set) var startedAt: Date?
    @Published private(set) var customMinutes = 90
    @Published private(set) var selectedEndTime: Date?
    @Published private(set) var now = Date()
    @Published var errorMessage: String?
    @Published private(set) var isScreenProtectionPaused = false
    private(set) var assertionIDs: [IOPMAssertionID] = []
    private(set) var userActivityID: IOPMAssertionID = 0
    private(set) var lastUserActivityAt: Date?
    private var ticker: AnyCancellable?
    private var wakeObservers: Set<AnyCancellable> = []
    private let consoleIsUnlocked: @MainActor () -> Bool
    private var activityToken: NSObjectProtocol?
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil, consoleIsUnlocked: @escaping @MainActor () -> Bool = AwakeSession.isConsoleUnlocked) {
        let defaults = defaults ?? AppDefaults.store
        self.defaults = defaults
        self.consoleIsUnlocked = consoleIsUnlocked
        if let saved = defaults.string(forKey: "awakeMode"), let value = AwakeMode(rawValue: saved) {
            mode = value
        }
        if let value = SessionDuration(rawValue: defaults.integer(forKey: "awakeDuration")) {
            duration = value
        }
        let savedMinutes = defaults.integer(forKey: "customMinutes")
        if (1...10080).contains(savedMinutes) { customMinutes = savedMinutes }
        if let savedTime = defaults.object(forKey: "selectedEndTime") as? Date, savedTime > Date() {
            selectedEndTime = savedTime
        } else if duration == .untilTime { duration = .forever }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
            .store(in: &wakeObservers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.releaseUserActivity() }
            .store(in: &wakeObservers)
    }

    var plannedDeadline: Date? {
        switch duration {
        case .forever: nil
        case .untilTime: selectedEndTime
        case .custom: now.addingTimeInterval(TimeInterval(customMinutes * 60))
        default: now.addingTimeInterval(TimeInterval(duration.rawValue))
        }
    }

    var durationTitle: String {
        switch duration {
        case .custom: Self.formatMinutes(customMinutes)
        case .untilTime: selectedEndTime.map { "Until " + $0.formatted(date: .omitted, time: .shortened) } ?? "Until a time"
        default: duration.title
        }
    }

    static func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    var progress: Double {
        guard let deadline, let startedAt else { return 1 }
        let total = deadline.timeIntervalSince(startedAt)
        return total > 0 ? max(0, min(1, deadline.timeIntervalSince(now) / total)) : 0
    }

    var remaining: String {
        guard let deadline else { return "Until you stop" }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%02d:%02d", minutes, seconds % 60)
    }

    var menuBarTime: String? {
        guard isActive, let deadline else { return nil }
        let minutes = max(1, Int(ceil(deadline.timeIntervalSince(now) / 60)))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    func toggle() { isActive ? stop() : start() }

    func start(resumingUntil savedDeadline: Date? = nil) {
        guard !isActive else { return }
        if let savedDeadline, savedDeadline <= Date() { return }
        do {
            isScreenProtectionPaused = mode == .display && !consoleIsUnlocked()
            assertionIDs = try acquire(isScreenProtectionPaused ? .system : mode)
            now = Date()
            let target = savedDeadline ?? plannedDeadline
            guard target == nil || target! > now else {
                stop()
                errorMessage = "That end time has passed. Choose a new time."
                return
            }
            deadline = target
            startedAt = now
            isActive = true
            activityToken = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Keep the idle-protection timer responsive")
            errorMessage = nil
            try maintainScreenProtection(at: now)
            ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                .sink { [weak self] date in self?.refresh(at: date) }
        } catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        if let activityToken { ProcessInfo.processInfo.endActivity(activityToken) }
        activityToken = nil
        releaseUserActivity()
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs = []
        isActive = false
        deadline = nil
        startedAt = nil
        isScreenProtectionPaused = false
    }

    func select(mode newMode: AwakeMode) {
        guard newMode != mode else { return }
        if isActive {
            do {
                let replacement = try acquire(newMode == .display && !consoleIsUnlocked() ? .system : newMode)
                assertionIDs.forEach { IOPMAssertionRelease($0) }
                assertionIDs = replacement
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        mode = newMode
        errorMessage = nil
        defaults.set(newMode.rawValue, forKey: "awakeMode")
        if isActive { refresh() }
    }

    func select(duration newDuration: SessionDuration) {
        guard newDuration != .untilTime || selectedEndTime != nil else { return }
        duration = newDuration
        errorMessage = nil
        defaults.set(newDuration.rawValue, forKey: "awakeDuration")
        if isActive {
            now = Date()
            deadline = plannedDeadline
            startedAt = now
            refresh()
        }
    }

    @discardableResult
    func setCustomDuration(hours: Int, minutes: Int) -> Bool {
        guard (0...168).contains(hours), (0...59).contains(minutes) else { return false }
        let total = hours * 60 + minutes
        guard (1...10080).contains(total) else { return false }
        customMinutes = total
        defaults.set(total, forKey: "customMinutes")
        select(duration: .custom)
        return true
    }

    @discardableResult
    func setEndTime(_ date: Date) -> Bool {
        let interval = date.timeIntervalSinceNow
        guard interval.isFinite, interval >= 1, interval <= 604800 else { return false }
        selectedEndTime = date
        defaults.set(date, forKey: "selectedEndTime")
        select(duration: .untilTime)
        return true
    }

    func refresh(at date: Date = Date()) {
        now = date
        if let deadline, date >= deadline { stop(); return }
        guard isActive else { return }
        do { try maintainScreenProtection(at: date) }
        catch {
            stop()
            errorMessage = error.localizedDescription
        }
    }

    private func maintainScreenProtection(at date: Date) throws {
        let paused = mode == .display && !consoleIsUnlocked()
        if paused != isScreenProtectionPaused {
            let replacement = try acquire(paused ? .system : mode)
            assertionIDs.forEach { IOPMAssertionRelease($0) }
            assertionIDs = replacement
            isScreenProtectionPaused = paused
        }
        guard mode == .display && !paused else {
            releaseUserActivity()
            return
        }
        // A display-sleep assertion alone does not declare the user active.
        // Refresh the OS activity assertion without generating keyboard/mouse events.
        guard lastUserActivityAt == nil || date.timeIntervalSince(lastUserActivityAt!) >= 15 else { return }
        let result = IOPMAssertionDeclareUserActivity("Stay Awake - idle protection" as CFString,
            kIOPMUserActiveLocal, &userActivityID)
        guard result == kIOReturnSuccess else {
            throw NSError(domain: "StayAwake.Activity", code: Int(result), userInfo: [
                NSLocalizedDescriptionKey: "macOS could not activate idle protection (\(result)). Try again."
            ])
        }
        lastUserActivityAt = date
    }

    private func releaseUserActivity() {
        if userActivityID != 0 { IOPMAssertionRelease(userActivityID) }
        userActivityID = 0
        lastUserActivityAt = nil
    }

    static func isConsoleUnlocked() -> Bool {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return false }
        defer { IOObjectRelease(root) }
        guard let locked = IORegistryEntryCreateCFProperty(root, "IOConsoleLocked" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool else { return false }
        guard !locked,
              let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString,
                kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]] else { return false }
        return users.contains {
            ($0["kCGSSessionOnConsoleKey"] as? Bool) == true &&
                ($0["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == getuid()
        }
    }

    private func acquire(_ mode: AwakeMode) throws -> [IOPMAssertionID] {
        var acquired: [IOPMAssertionID] = []
        for type in mode.assertionTypes {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Stay Awake — \(mode.title)" as CFString, &id)
            guard result == kIOReturnSuccess else {
                acquired.forEach { IOPMAssertionRelease($0) }
                throw NSError(domain: "StayAwake.Power", code: Int(result),
                    userInfo: [NSLocalizedDescriptionKey: "macOS could not keep this Mac awake (\(result)). Try again."])
            }
            acquired.append(id)
        }
        return acquired
    }

    // Real OS readback, used by the command-line lifecycle check.
    func verifiedAssertionTypes() -> Set<String> {
        Set((assertionIDs + (userActivityID == 0 ? [] : [userActivityID])).compactMap { id in
            guard let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any],
                  let level = properties[kIOPMAssertionLevelKey] as? Int, level == kIOPMAssertionLevelOn
            else { return nil }
            return properties[kIOPMAssertionTypeKey] as? String
        })
    }
}
