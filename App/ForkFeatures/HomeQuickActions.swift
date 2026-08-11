import Combine
import Foundation
import UIKit

enum HomeQuickAction: Equatable {
    case favorite(UUID)
    case clearVirtualLocation
    case enhancements
}

@MainActor
final class HomeQuickActionManager: ObservableObject {
    static let shared = HomeQuickActionManager()

    private enum ActionType {
        static let favoritePrefix = "com.paopaolabs.location-spoofer.quick.favorite."
        static let clear = "com.paopaolabs.location-spoofer.quick.clear"
        static let enhancements = "com.paopaolabs.location-spoofer.quick.enhancements"
    }

    @Published private(set) var pendingAction: HomeQuickAction?

    private init() {}

    func refresh() {
        let recent = RecentFavoriteStore.recentFavorites(limit: 2)
        var items = recent.map { favorite in
            UIApplicationShortcutItem(
                type: ActionType.favoritePrefix + favorite.id.uuidString,
                localizedTitle: favorite.name,
                localizedSubtitle: "设置虚拟定位",
                icon: UIApplicationShortcutIcon(systemImageName: "location.fill"),
                userInfo: nil
            )
        }
        items.append(
            UIApplicationShortcutItem(
                type: ActionType.clear,
                localizedTitle: "关闭虚拟定位",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "location.slash"),
                userInfo: nil
            )
        )
        items.append(
            UIApplicationShortcutItem(
                type: ActionType.enhancements,
                localizedTitle: "增强功能",
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: "sparkles"),
                userInfo: nil
            )
        )
        UIApplication.shared.shortcutItems = items
    }

    @discardableResult
    func receive(_ item: UIApplicationShortcutItem) -> Bool {
        if item.type == ActionType.clear {
            pendingAction = .clearVirtualLocation
            return true
        }
        if item.type == ActionType.enhancements {
            pendingAction = .enhancements
            return true
        }
        guard item.type.hasPrefix(ActionType.favoritePrefix) else { return false }
        let value = String(item.type.dropFirst(ActionType.favoritePrefix.count))
        guard let id = UUID(uuidString: value) else { return false }
        pendingAction = .favorite(id)
        return true
    }

    func consume() -> HomeQuickAction? {
        defer { pendingAction = nil }
        return pendingAction
    }
}

final class LocationSpooferSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let item = connectionOptions.shortcutItem {
            Task { @MainActor in
                _ = HomeQuickActionManager.shared.receive(item)
            }
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Task { @MainActor in
            HomeQuickActionManager.shared.refresh()
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            completionHandler(HomeQuickActionManager.shared.receive(shortcutItem))
        }
    }
}

final class LocationSpooferApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = LocationSpooferSceneDelegate.self
        return configuration
    }
}
