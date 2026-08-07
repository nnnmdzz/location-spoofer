import Foundation

@MainActor
enum WlocAccuracyPreset: Int, CaseIterable, Identifiable {
    case standard = 25
    case enhanced = 10
    case high = 5
    case experimental = 1

    var id: Int { rawValue }

    var displayName: String { "\(rawValue) m" }

    var detail: String {
        switch self {
        case .standard:
            return "上游默认值，行为最保守"
        case .enhanced:
            return "较高精度，建议优先尝试"
        case .high:
            return "高精度，用于强 GPS 环境对比"
        case .experimental:
            return "实验值，可能提高权重，也可能被系统判定为异常来源"
        }
    }
}

@MainActor
final class WlocAccuracyPreference: ObservableObject {
    static let shared = WlocAccuracyPreference()
    static let allowedRange = 1...1000

    private enum Key {
        static let selectedAccuracy = "wloc_accuracy_preference_meters"
    }

    @Published private(set) var meters: Int
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: Key.selectedAccuracy)
        self.meters = Self.allowedRange.contains(stored) ? stored : WlocAccuracyPreset.standard.rawValue
    }

    var matchingPreset: WlocAccuracyPreset? {
        WlocAccuracyPreset(rawValue: meters)
    }

    var isCustom: Bool { matchingPreset == nil }

    func select(_ preset: WlocAccuracyPreset) {
        setMeters(preset.rawValue, source: "预设")
    }

    @discardableResult
    func setCustomMeters(_ value: Int) -> Bool {
        guard Self.allowedRange.contains(value) else { return false }
        setMeters(value, source: "自定义")
        return true
    }

    private func setMeters(_ value: Int, source: String) {
        guard meters != value else { return }
        meters = value
        defaults.set(value, forKey: Key.selectedAccuracy)
        RuntimeLogger.info("APP", "WLOC精度", "已更新 WLOC 精度配置", details: [
            "accuracy": String(value),
            "来源": source
        ])
    }
}
