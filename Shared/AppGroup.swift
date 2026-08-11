import Foundation

enum AppGroup {
    static let identifier = "group.com.paopaolabs.location-spoofer"
    static let defaults = UserDefaults(suiteName: identifier) ?? .standard

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var isSharedContainerAvailable: Bool { sharedContainerURL != nil }

    static var containerURL: URL {
        if let url = sharedContainerURL { return url }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocationSpoofer", isDirectory: true)
    }
}

enum WlocKeys {
    static let coords = "wloc_settings"
}

struct WlocSettings: Codable {
    var longitude: Double
    var latitude: Double
    var accuracy: Int
    var enabled: Bool
}

enum WlocSettingsStore {
    static func load() -> WlocSettings? {
        guard let data = AppGroup.defaults.data(forKey: WlocKeys.coords) else { return nil }
        return try? JSONDecoder().decode(WlocSettings.self, from: data)
    }

    static func save(_ settings: WlocSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        AppGroup.defaults.set(data, forKey: WlocKeys.coords)
    }

    static func clear() {
        save(WlocSettings(longitude: 0, latitude: 0, accuracy: 25, enabled: false))
    }
}

@MainActor
final class MotionSimulationStore: ObservableObject {
    static let shared = MotionSimulationStore()

    private enum Key {
        static let enabled = "motionSimulation.enabled"
    }

    @Published private(set) var isEnabled: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Key.enabled)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.enabled)
    }
}

@MainActor
final class ThirdPartyModuleSourceStore: ObservableObject {
    static let shared = ThirdPartyModuleSourceStore()

    private enum Key {
        static let useMirror = "thirdPartyModule.useMirror"
    }

    @Published private(set) var useMirror: Bool
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        useMirror = defaults.object(forKey: Key.useMirror) as? Bool ?? true
    }

    func setUseMirror(_ enabled: Bool) {
        useMirror = enabled
        defaults.set(enabled, forKey: Key.useMirror)
    }
}

enum VirtualLocationTipKind: Equatable {
    case activation
    case deactivation
}

/// Owns the persistent counters and suppression flags for automatic operation tips.
/// Manual help sheets do not consult or mutate this store.
struct VirtualLocationTipPreferences {
    static let minimumCountForSuppression = 3

    private enum Key {
        static let activationCount = "virtualLocationTip.activationCount"
        static let deactivationCount = "virtualLocationTip.deactivationCount"
        static let activationSuppressed = "virtualLocationTip.activationSuppressed"
        static let deactivationSuppressed = "virtualLocationTip.deactivationSuppressed"
        static let legacyActivationSuppressed = "activationTipDisabled"
    }

    private let defaults: UserDefaults
    private let legacyDefaults: UserDefaults

    init(
        defaults: UserDefaults = AppGroup.defaults,
        legacyDefaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
    }

    @discardableResult
    func recordSuccessfulOperation(_ kind: VirtualLocationTipKind) -> Int {
        let key = countKey(for: kind)
        let next = defaults.integer(forKey: key) + 1
        defaults.set(next, forKey: key)
        return next
    }

    func shouldPresentAutomaticTip(_ kind: VirtualLocationTipKind) -> Bool {
        !isSuppressed(kind)
    }

    func canSuppress(_ kind: VirtualLocationTipKind) -> Bool {
        defaults.integer(forKey: countKey(for: kind)) >= Self.minimumCountForSuppression
    }

    func suppress(_ kind: VirtualLocationTipKind) {
        guard canSuppress(kind) else { return }
        defaults.set(true, forKey: suppressionKey(for: kind))
    }

    private func isSuppressed(_ kind: VirtualLocationTipKind) -> Bool {
        if kind == .activation,
           legacyDefaults.bool(forKey: Key.legacyActivationSuppressed) {
            return true
        }
        return defaults.bool(forKey: suppressionKey(for: kind))
    }

    private func countKey(for kind: VirtualLocationTipKind) -> String {
        switch kind {
        case .activation: return Key.activationCount
        case .deactivation: return Key.deactivationCount
        }
    }

    private func suppressionKey(for kind: VirtualLocationTipKind) -> String {
        switch kind {
        case .activation: return Key.activationSuppressed
        case .deactivation: return Key.deactivationSuppressed
        }
    }
}

/// Controls the optional prompt asking users to share a verified third-party setup.
struct ThirdPartyCommunityPromptPreferences {
    static let minimumCountForSuppression = 3

    private enum Key {
        static let presentationCount = "thirdPartyCommunityPrompt.presentationCount"
        static let suppressed = "thirdPartyCommunityPrompt.suppressed"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    @discardableResult
    func recordPresentation() -> Int {
        let next = defaults.integer(forKey: Key.presentationCount) + 1
        defaults.set(next, forKey: Key.presentationCount)
        return next
    }

    func shouldPresent() -> Bool {
        !defaults.bool(forKey: Key.suppressed)
    }

    func canSuppress() -> Bool {
        defaults.integer(forKey: Key.presentationCount) >= Self.minimumCountForSuppression
    }

    func suppress() {
        guard canSuppress() else { return }
        defaults.set(true, forKey: Key.suppressed)
    }
}
