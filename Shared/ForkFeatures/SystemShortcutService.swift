import Combine
import Foundation
import UIKit

enum SavedShortcutInputMode: String, Codable, CaseIterable, Identifiable {
    case none
    case fixedText
    case clipboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无输入"
        case .fixedText: return "固定文本"
        case .clipboard: return "当前剪贴板"
        }
    }
}

struct SavedSystemShortcut: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var inputMode: SavedShortcutInputMode
    var fixedText: String

    init(
        id: UUID = UUID(),
        name: String,
        inputMode: SavedShortcutInputMode = .none,
        fixedText: String = ""
    ) {
        self.id = id
        self.name = name
        self.inputMode = inputMode
        self.fixedText = fixedText
    }
}

@MainActor
final class SavedSystemShortcutStore: ObservableObject {
    private static let key = "fork_saved_system_shortcuts"

    @Published private(set) var items: [SavedSystemShortcut]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([SavedSystemShortcut].self, from: data) {
            items = decoded
        } else {
            items = []
        }
    }

    func upsert(_ item: SavedSystemShortcut) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        persist()
    }

    func delete(_ item: SavedSystemShortcut) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

@MainActor
final class SystemShortcutCallbackRouter: ObservableObject {
    static let shared = SystemShortcutCallbackRouter()

    private static let pendingNonceKey = "fork_shortcut_callback_nonce"
    static let callbackScheme = "paopaolocation-spoofer"
    static let callbackHost = "shortcut-callback"

    @Published private(set) var lastMessage: String?
    @Published private(set) var lastWasError = false

    private init() {}

    func prepareRun() -> UUID {
        let nonce = UUID()
        AppGroup.defaults.set(nonce.uuidString, forKey: Self.pendingNonceKey)
        lastMessage = nil
        lastWasError = false
        return nonce
    }

    func markOpenFailure() {
        AppGroup.defaults.removeObject(forKey: Self.pendingNonceKey)
        lastMessage = "无法打开快捷指令 App，请确认系统快捷指令可用。"
        lastWasError = true
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == Self.callbackScheme,
              url.host == Self.callbackHost else { return false }
        let status = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard ["success", "cancel", "error"].contains(status),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let nonce = components.queryItems?.first(where: { $0.name == "nonce" })?.value,
              nonce == AppGroup.defaults.string(forKey: Self.pendingNonceKey) else {
            return false
        }

        AppGroup.defaults.removeObject(forKey: Self.pendingNonceKey)
        let queryItems = components.queryItems ?? []
        switch status {
        case "success":
            let result = queryItems.first(where: { $0.name == "result" })?.value
                ?.trimmingCharacters(in: .whitespacesAndNewlines)
            lastMessage = (result?.isEmpty == false) ? result : "快捷指令执行完成。"
            lastWasError = false
        case "cancel":
            lastMessage = "快捷指令已取消。"
            lastWasError = false
        default:
            let errorMessage = queryItems.first(where: { $0.name == "errorMessage" })?.value
                ?.trimmingCharacters(in: .whitespacesAndNewlines)
            lastMessage = (errorMessage?.isEmpty == false) ? errorMessage : "快捷指令执行失败。"
            lastWasError = true
        }
        return true
    }

    func clearResult() {
        lastMessage = nil
        lastWasError = false
    }
}

@MainActor
enum SystemShortcutRunner {
    static func run(_ shortcut: SavedSystemShortcut) {
        let name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let nonce = SystemShortcutCallbackRouter.shared.prepareRun()

        let success = callbackURL(status: "success", nonce: nonce)
        let cancel = callbackURL(status: "cancel", nonce: nonce)
        let error = callbackURL(status: "error", nonce: nonce)

        var components = URLComponents()
        components.scheme = "shortcuts"
        components.host = "x-callback-url"
        components.path = "/run-shortcut"
        var queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "x-success", value: success.absoluteString),
            URLQueryItem(name: "x-cancel", value: cancel.absoluteString),
            URLQueryItem(name: "x-error", value: error.absoluteString),
        ]
        switch shortcut.inputMode {
        case .none:
            break
        case .fixedText:
            queryItems.append(URLQueryItem(name: "input", value: "text"))
            queryItems.append(URLQueryItem(name: "text", value: shortcut.fixedText))
        case .clipboard:
            queryItems.append(URLQueryItem(name: "input", value: "clipboard"))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            SystemShortcutCallbackRouter.shared.markOpenFailure()
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened else { return }
            Task { @MainActor in
                SystemShortcutCallbackRouter.shared.markOpenFailure()
            }
        }
    }

    static func openShortcutsApp() {
        guard let url = URL(string: "shortcuts://") else { return }
        UIApplication.shared.open(url)
    }

    private static func callbackURL(status: String, nonce: UUID) -> URL {
        var components = URLComponents()
        components.scheme = SystemShortcutCallbackRouter.callbackScheme
        components.host = SystemShortcutCallbackRouter.callbackHost
        components.path = "/\(status)"
        components.queryItems = [URLQueryItem(name: "nonce", value: nonce.uuidString)]
        return components.url!
    }
}
