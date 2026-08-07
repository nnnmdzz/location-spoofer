import Foundation

@MainActor
protocol LocationActionProxying: AnyObject {
    var isRunning: Bool { get }
    func start() async throws
    func setCoords(lat: Double, lon: Double, enabled: Bool, accuracy: Int) -> UInt64
}

extension ProxyManager: LocationActionProxying {}

@MainActor
protocol LocationActionSettingsStoring: AnyObject {
    func load() -> WlocSettings?
    func save(_ settings: WlocSettings)
    func clear()
}

@MainActor
final class DeviceWlocSettingsStorage: LocationActionSettingsStoring {
    func load() -> WlocSettings? { WlocSettingsStore.load() }
    func save(_ settings: WlocSettings) { WlocSettingsStore.save(settings) }
    func clear() { WlocSettingsStore.clear() }
}

@MainActor
final class LocationActionCoordinator: ObservableObject {
    @Published private(set) var state: LocationActionState = .idle
    @Published private(set) var virtualLocationEnabled = false
    @Published private(set) var message = ""

    private let proxy: any LocationActionProxying
    private let settings: any LocationActionSettingsStoring
    private let effectMonitor: LocationEffectMonitor?

    init() {
        self.proxy = ProxyManager.shared
        self.settings = DeviceWlocSettingsStorage()
        self.effectMonitor = .shared
        let existing = settings.load()
        self.virtualLocationEnabled = existing?.enabled == true
        if ProxyRuntimeModeStore.shared.mode == .localWiFi,
           let existing,
           existing.enabled {
            effectMonitor?.restoreActiveTarget(.init(
                latitude: existing.latitude,
                longitude: existing.longitude
            ))
        }
    }

    init(proxy: any LocationActionProxying, settings: any LocationActionSettingsStoring) {
        self.proxy = proxy
        self.settings = settings
        self.effectMonitor = nil
        self.virtualLocationEnabled = settings.load()?.enabled == true
    }

    func apply(_ favorite: FavoriteLocation) async -> Bool {
        guard beginApply() else { return false }
        do {
            if !proxy.isRunning { try await proxy.start() }
            guard !Task.isCancelled else {
                finishCancelledApply()
                return false
            }
            return commit(favorite)
        } catch {
            failApply(error)
            return false
        }
    }

    /// Commits a target after SetupCoordinator has completed verification.
    /// This method is synchronous on MainActor so selection revision validation
    /// and the final settings/proxy write cannot be interleaved by a newer map event.
    func applyVerified(_ favorite: FavoriteLocation) -> Bool {
        guard proxy.isRunning else {
            failApply(ProxyError.startFailed)
            return false
        }
        guard beginApply() else { return false }
        return commit(favorite)
    }

    func clear() {
        guard !state.isBusy else { return }
        _ = proxy.setCoords(
            lat: 0,
            lon: 0,
            enabled: false,
            accuracy: WlocAccuracyPreference.shared.meters
        )
        settings.clear()
        effectMonitor?.clear()
        state = .idle
        virtualLocationEnabled = false
        message = "已恢复真实定位"
    }

    private func beginApply() -> Bool {
        guard !state.isBusy else { return false }
        state = .applyingLocation
        message = "启动代理…"
        return true
    }

    private func commit(_ favorite: FavoriteLocation) -> Bool {
        // WLOC 合约固定使用持久化的 WGS-84 值，不依赖当前地图坐标标准。
        // Accuracy is a global runtime preference so old favorites do not need migration.
        let wgs = favorite.coordinatePair.wgs84
        let accuracy = WlocAccuracyPreference.shared.meters
        let value = WlocSettings(
            longitude: wgs.longitude,
            latitude: wgs.latitude,
            accuracy: accuracy,
            enabled: true
        )
        settings.save(value)
        _ = proxy.setCoords(
            lat: wgs.latitude,
            lon: wgs.longitude,
            enabled: true,
            accuracy: accuracy
        )
        effectMonitor?.activate(target: .init(latitude: wgs.latitude, longitude: wgs.longitude))
        RuntimeLogger.info("APP", "坐标转换", "设置虚拟定位坐标", details: [
            "WLOC写入标准": CoordinateConverter.MapCoordinateSystem.wgs84.diagnosticName,
            "当前地图标准": CoordinateConverter.currentMapCoordinateSystem.diagnosticName,
            "目标所在区域": CoordinateConverter.usesGCJ02ServiceArea(lat: wgs.latitude, lon: wgs.longitude) ? "国内转换区域" : "国外非转换区域",
            "取值字段": "coordinatePair.wgs84",
            "accuracy": String(accuracy),
            "accuracy来源": "全局WLOC精度配置"
        ])
        state = .idle
        virtualLocationEnabled = true
        message = "虚拟定位已开启"
        return true
    }

    private func finishCancelledApply() {
        state = .idle
        message = "已取消位置更新"
    }

    private func failApply(_ error: Error) {
        virtualLocationEnabled = false
        message = "启动失败"
        state = .failed(error.localizedDescription)
        RuntimeLogger.error("APP", "Location", "apply失败", error: error)
    }
}
