import AppIntents
import Foundation

@available(iOS 16.0, *)
struct FavoriteLocationEntity: AppEntity, Sendable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "收藏位置")
    static var defaultQuery = FavoriteLocationEntityQuery()

    let id: UUID

    @Property(title: "名称")
    var name: String

    @Property(title: "WGS-84 纬度")
    var latitude: Double

    @Property(title: "WGS-84 经度")
    var longitude: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(iOS 16.0, *)
struct FavoriteLocationEntityQuery: EntityQuery, Sendable {
    func entities(for identifiers: [UUID]) async throws -> [FavoriteLocationEntity] {
        let requested = Set(identifiers)
        return FavoriteLocationStore().favorites
            .filter { requested.contains($0.id) }
            .map(FavoriteLocationEntity.init)
    }

    func suggestedEntities() async throws -> [FavoriteLocationEntity] {
        FavoriteLocationStore().favorites.map(FavoriteLocationEntity.init)
    }
}

@available(iOS 16.0, *)
private extension FavoriteLocationEntity {
    init(_ favorite: FavoriteLocation) {
        id = favorite.id
        name = favorite.name
        latitude = favorite.latitude
        longitude = favorite.longitude
    }
}

@available(iOS 16.0, *)
struct GetFavoriteLocationsIntent: AppIntent {
    static var title: LocalizedStringResource = "获取收藏位置"
    static var description = IntentDescription("返回 Location Spoofer 中保存的收藏位置列表和对应 WGS-84 坐标。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[FavoriteLocationEntity]> {
        .result(value: FavoriteLocationStore().favorites.map(FavoriteLocationEntity.init))
    }
}

@available(iOS 16.0, *)
struct SetFavoriteVirtualLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "设置虚拟定位"
    static var description = IntentDescription("把 Location Spoofer 的虚拟定位切换到一个已收藏的位置。")
    static var openAppWhenRun = false

    @Parameter(title: "收藏位置")
    var favorite: FavoriteLocationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("将虚拟定位设置为 \(\.$favorite)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ShortcutLocationService.applyFavorite(id: favorite.id)
        return .result(dialog: "\(message)")
    }
}

@available(iOS 16.0, *)
struct ClearVirtualLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭虚拟定位"
    static var description = IntentDescription("清除当前运行模式保存的虚拟定位。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ShortcutLocationService.clear()
        return .result(dialog: "\(message)")
    }
}

@available(iOS 16.0, *)
struct VirtualLocationStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "查看虚拟定位状态"
    static var description = IntentDescription("读取当前运行模式和已保存的虚拟定位状态。")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await ShortcutLocationService.status()
        return .result(dialog: "\(message)")
    }
}

@available(iOS 16.0, *)
struct LocationSpooferAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetFavoriteLocationsIntent(),
            phrases: [
                "获取 \(.applicationName) 收藏位置",
                "查看 \(.applicationName) 收藏列表"
            ],
            shortTitle: "获取收藏位置",
            systemImageName: "star.fill"
        )

        AppShortcut(
            intent: SetFavoriteVirtualLocationIntent(),
            phrases: [
                "用 \(.applicationName) 设置虚拟定位",
                "在 \(.applicationName) 切换虚拟位置"
            ],
            shortTitle: "设置虚拟定位",
            systemImageName: "location.fill"
        )

        AppShortcut(
            intent: ClearVirtualLocationIntent(),
            phrases: [
                "用 \(.applicationName) 关闭虚拟定位",
                "在 \(.applicationName) 恢复真实定位"
            ],
            shortTitle: "关闭虚拟定位",
            systemImageName: "location.slash"
        )

        AppShortcut(
            intent: VirtualLocationStatusIntent(),
            phrases: [
                "查看 \(.applicationName) 虚拟定位状态",
                "\(.applicationName) 当前定位状态"
            ],
            shortTitle: "虚拟定位状态",
            systemImageName: "location.circle"
        )
    }
}
