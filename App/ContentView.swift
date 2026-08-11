import SwiftUI

struct ContentView: View {
    @StateObject private var setup = SetupCoordinator()
    @ObservedObject private var runtimeMode = ProxyRuntimeModeStore.shared
    @ObservedObject private var quickActions = HomeQuickActionManager.shared
    @State private var phase: AppPhase = .splash
    @State private var showingEnhancements = false
    @State private var quickActionMessage = ""

    enum AppPhase { case splash, setup, map }

    var body: some View {
        Group {
            switch phase {
            case .splash:
                VStack(spacing: 16) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 48)).foregroundStyle(.blue)
                    ProgressView()
                    Text(runtimeMode.hasSelectedMode && runtimeMode.mode == .localWiFi
                         ? "正在初始化地图与本地代理…"
                         : "正在初始化地图…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            case .setup:
                FirstSetupView(setup: setup, onComplete: finishInitialSetup)
            case .map:
                NavigationView {
                    MapHomeView(setup: setup) {
                        showingEnhancements = true
                    }
                }
                .fullScreenCover(isPresented: $setup.needsSetup) {
                    FirstSetupView(setup: setup, onComplete: finishPresentedSetup)
                }
            }
        }
        .sheet(isPresented: $showingEnhancements) {
            NavigationView {
                ForkEnhancementsView()
            }
        }
        .alert("快捷操作", isPresented: Binding(
            get: { !quickActionMessage.isEmpty },
            set: { if !$0 { quickActionMessage = "" } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(quickActionMessage)
        }
        .task { await bootstrap() }
        .onChange(of: quickActions.pendingAction) { _ in
            Task { @MainActor in
                await handlePendingQuickActionIfReady()
            }
        }
    }

    @MainActor
    private func bootstrap() async {
        guard runtimeMode.hasSelectedMode else {
            ProxyManager.shared.stop()
            RuntimeLogger.info("APP", "Startup", "尚未选择运行模式，跳过本地 CA 和代理初始化")
            setup.requestModeSelection()
            phase = .setup
            return
        }

        let launchMode = runtimeMode.mode
        guard runtimeMode.isInitialized(launchMode) else {
            if launchMode == .localWiFi {
                await setup.prepareLocalServices()
                setup.requestSetup()
            } else {
                ProxyManager.shared.stop()
                BackgroundKeepAlive.shared.stop()
                setup.requestThirdPartyOnboarding()
            }
            phase = .setup
            return
        }

        if launchMode == .localWiFi {
            await setup.prepareLocalServices()
        } else {
            ProxyManager.shared.stop()
            BackgroundKeepAlive.shared.stop()
            RuntimeLogger.info("APP", "Startup", "第三方代理测试模式：跳过本地 CA、代理和环境检测")
        }
        do {
            try CoordinateStorageMigration.migrateIfNeeded(favorites: FavoriteLocationStore())
        } catch {
            RuntimeLogger.error("APP", "Startup", "旧坐标数据迁移失败，将在下次启动重试", error: error)
        }

        // MapHomeView is intentionally constructed only after this required
        // coordinate-system gate resolves, so cached pins are never replayed
        // into an unknown Apple Maps coordinate system.
        let mapCoordinateSystem = await CoordinateConverter.resolveInitialMapCoordinateSystem()
        guard !Task.isCancelled else { return }
        RuntimeLogger.info("APP", "Startup", "地图坐标标准初始化完成，开始后续启动流程", details: [
            "地图标准": mapCoordinateSystem.rawValue,
            "使用兜底": String(CoordinateConverter.initialMapCoordinateSystemUsedFallback)
        ])

        // Resolve the first map center before constructing MapHomeView. This
        // prevents a Shenzhen/cache frame followed by a second realtime frame.
        if LastCoordinateStore.load() == nil {
            RuntimeLogger.info("APP", "Startup", "没有持久化图钉，地图创建前请求实时定位")
            if let realtime = await RealtimeLocationManager.shared.requestLocation() {
                let mapCoordinateSystemChange = CoordinateConverter.correctMapCoordinateSystemUsingRealtime(realtime)
                let pair = CoordinateConverter.coordinatePair(
                    lat: realtime.latitude,
                    lon: realtime.longitude,
                    mapCoordinateSystem: .wgs84
                )
                LastCoordinateStore.save(coordinatePair: pair, zoomMeters: 1_000)
                RuntimeLogger.info("APP", "Startup", "已使用实时定位准备唯一初始地图状态", details: [
                    "地图标准": CoordinateConverter.currentMapCoordinateSystem.rawValue,
                    "修正兜底标准": String(mapCoordinateSystemChange != nil),
                    "缩放米": "1000"
                ])
                RealtimeLocationTrace.coordinate(
                    "地图创建前取得的初始实时位置（WGS-84）",
                    coordinate: realtime
                )
            } else {
                RuntimeLogger.warning("APP", "Startup", "地图创建前无法取得实时定位，唯一初始位置使用深圳", details: [
                    "地图标准": mapCoordinateSystem.rawValue,
                    "缩放米": "1000"
                ])
            }
        } else {
            RuntimeLogger.info("APP", "Startup", "已找到持久化图钉，直接准备唯一初始地图状态")
        }
        guard !Task.isCancelled else { return }

        setup.completeSetup()
        RuntimeLogger.info("APP", "Startup", "启动门禁全部完成，现在创建 MapHomeView")
        phase = .map
        HomeQuickActionManager.shared.refresh()
        await handlePendingQuickActionIfReady()
    }

    private func finishInitialSetup() {
        let completedMode = runtimeMode.mode
        runtimeMode.markInitialized(completedMode)
        setup.completeSetup()
        phase = .splash
        Task { await bootstrap() }
    }

    private func finishPresentedSetup() {
        runtimeMode.markInitialized(runtimeMode.mode)
        setup.completeSetup()
    }

    @MainActor
    private func handlePendingQuickActionIfReady() async {
        guard phase == .map, let action = quickActions.consume() else { return }
        switch action {
        case .enhancements:
            showingEnhancements = true
        case .favorite(let id):
            do {
                quickActionMessage = try await ShortcutLocationService.applyFavorite(id: id)
            } catch {
                HomeQuickActionManager.shared.refresh()
                quickActionMessage = error.localizedDescription
            }
        case .clearVirtualLocation:
            do {
                quickActionMessage = try await ShortcutLocationService.clear()
            } catch {
                quickActionMessage = error.localizedDescription
            }
        }
    }
}
