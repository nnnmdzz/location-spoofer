import Foundation

enum ShortcutLocationServiceError: LocalizedError {
    case runtimeModeNotSelected
    case runtimeModeNotInitialized(String)
    case favoriteNotFound
    case localApplyFailed(String)

    var errorDescription: String? {
        switch self {
        case .runtimeModeNotSelected:
            return "尚未选择运行模式，请先打开 Location Spoofer 完成初始配置。"
        case .runtimeModeNotInitialized(let mode):
            return "\(mode)尚未完成配置，请先打开 Location Spoofer 完成该模式的引导。"
        case .favoriteNotFound:
            return "找不到这个收藏位置，它可能已经在 App 中被删除。"
        case .localApplyFailed(let message):
            return message.isEmpty ? "APP 模式设置虚拟定位失败。" : message
        }
    }
}

@MainActor
enum ShortcutLocationService {
    static func applyFavorite(id: UUID) async throws -> String {
        let runtime = ProxyRuntimeModeStore.shared
        try validateRuntime(runtime)

        let store = FavoriteLocationStore()
        guard let favorite = store.favorites.first(where: { $0.id == id }) else {
            throw ShortcutLocationServiceError.favoriteNotFound
        }

        switch runtime.mode {
        case .localWiFi:
            let coordinator = LocationActionCoordinator()
            guard await coordinator.apply(favorite) else {
                throw ShortcutLocationServiceError.localApplyFailed(coordinator.message)
            }
        case .thirdParty:
            _ = try await ThirdPartyProxyManager.shared.save(favorite)
        }

        store.select(favorite.id)
        RuntimeLogger.info("APP", "Shortcuts", "快捷指令已设置收藏位置", details: [
            "收藏": favorite.name,
            "模式": runtime.mode.displayName,
            "坐标标准": "WGS-84",
            "accuracy": String(WlocAccuracyPreference.shared.meters)
        ])
        return "已将虚拟定位设置为“\(favorite.name)”（\(runtime.mode.displayName)）。"
    }

    static func clear() async throws -> String {
        let runtime = ProxyRuntimeModeStore.shared
        try validateRuntime(runtime)

        switch runtime.mode {
        case .localWiFi:
            LocationActionCoordinator().clear()
        case .thirdParty:
            try await ThirdPartyProxyManager.shared.clear()
        }

        RuntimeLogger.info("APP", "Shortcuts", "快捷指令已关闭虚拟定位", details: [
            "模式": runtime.mode.displayName
        ])
        return "已关闭虚拟定位（\(runtime.mode.displayName)）。"
    }

    static func status() async throws -> String {
        let runtime = ProxyRuntimeModeStore.shared
        guard runtime.hasSelectedMode else {
            return "尚未选择运行模式。"
        }

        switch runtime.mode {
        case .localWiFi:
            guard let settings = WlocSettingsStore.load(), settings.enabled else {
                return "APP 模式：虚拟定位未开启。"
            }
            let name = favoriteName(latitude: settings.latitude, longitude: settings.longitude)
            let target = name.map { "“\($0)”" }
                ?? String(format: "%.6f, %.6f", settings.latitude, settings.longitude)
            return "APP 模式：虚拟定位已开启，目标 \(target)，WLOC 精度 \(settings.accuracy)m。"

        case .thirdParty:
            let response = try await ThirdPartyProxyManager.shared.query()
            guard response.success,
                  let latitude = response.latitude,
                  let longitude = response.longitude else {
                return "第三方代理模式：当前没有已保存的虚拟定位。"
            }
            let name = favoriteName(latitude: latitude, longitude: longitude)
            let target = name.map { "“\($0)”" }
                ?? String(format: "%.6f, %.6f", latitude, longitude)
            let accuracy = response.accuracy ?? WlocAccuracyPreference.shared.meters
            return "第三方代理模式：虚拟定位已开启，目标 \(target)，WLOC 精度 \(accuracy)m。"
        }
    }

    private static func validateRuntime(_ runtime: ProxyRuntimeModeStore) throws {
        guard runtime.hasSelectedMode else {
            throw ShortcutLocationServiceError.runtimeModeNotSelected
        }
        guard runtime.isInitialized(runtime.mode) else {
            throw ShortcutLocationServiceError.runtimeModeNotInitialized(runtime.mode.displayName)
        }
    }

    private static func favoriteName(latitude: Double, longitude: Double) -> String? {
        FavoriteLocationStore().favorites.first {
            $0.coordinatePair.matchesWGS84(latitude: latitude, longitude: longitude)
        }?.name
    }
}
