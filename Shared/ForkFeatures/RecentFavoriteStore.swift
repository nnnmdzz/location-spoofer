import Foundation

enum RecentFavoriteStore {
    private static let key = "fork_recent_favorite_ids"
    private static let maximumStoredCount = 8

    static func record(_ id: UUID, defaults: UserDefaults = AppGroup.defaults) {
        var ids = loadIDs(defaults: defaults)
        ids.removeAll { $0 == id }
        ids.insert(id, at: 0)
        defaults.set(Array(ids.prefix(maximumStoredCount)).map(\.uuidString), forKey: key)
    }

    static func recentFavorites(
        limit: Int = 2,
        defaults: UserDefaults = AppGroup.defaults,
        favorites: [FavoriteLocation]? = nil
    ) -> [FavoriteLocation] {
        let available = favorites ?? FavoriteLocationStore(defaults: defaults).favorites
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        let storedIDs = loadIDs(defaults: defaults)
        let validIDs = storedIDs.filter { byID[$0] != nil }
        if validIDs != storedIDs {
            defaults.set(validIDs.map(\.uuidString), forKey: key)
        }
        return validIDs.prefix(max(0, limit)).compactMap { byID[$0] }
    }

    private static func loadIDs(defaults: UserDefaults) -> [UUID] {
        (defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
    }
}
