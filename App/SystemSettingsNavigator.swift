import Foundation
import UIKit

enum SystemSettingsDestination {
    case appPermissions
    case general
    case wifi
    case locationServices

    var preferredURLs: [URL] {
        let values: [String]
        switch self {
        case .appPermissions:
            values = [UIApplication.openSettingsURLString]
        case .general:
            values = ["App-Prefs:General"]
        case .wifi:
            values = ["App-Prefs:WIFI"]
        case .locationServices:
            values = [
                "prefs:root=Privacy&path=LOCATION",
                "App-Prefs:root=Privacy&path=LOCATION",
                "App-Prefs:Privacy&path=LOCATION"
            ]
        }
        return values.compactMap(URL.init(string:))
    }

    // Compatibility for existing call sites that only try one private URL.
    // Location Services therefore uses the requested `prefs:` shortcut first.
    var preferredURL: URL? { preferredURLs.first }

    var manualPath: String {
        switch self {
        case .appPermissions:
            return "请手动打开「设置」，找到本 App 后检查定位权限。"
        case .general:
            return "请手动打开「设置 → 通用」。"
        case .wifi:
            return "请手动打开「设置 → 无线局域网」，进入当前 Wi-Fi 的详情页。"
        case .locationServices:
            return "请手动打开「设置 → 隐私与安全性 → 定位服务」。"
        }
    }
}

@MainActor
enum SystemSettingsNavigator {
    static func open(
        _ destination: SystemSettingsDestination,
        completion: @escaping @MainActor @Sendable (String?) -> Void = { _ in }
    ) {
        let appSettingsURL = URL(string: UIApplication.openSettingsURLString)
        let candidates = destination.preferredURLs + [appSettingsURL].compactMap { $0 }
        openFirstAvailable(
            candidates,
            manualPath: destination.manualPath,
            completion: completion
        )
    }

    private static func openFirstAvailable(
        _ urls: [URL],
        manualPath: String,
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        guard let first = urls.first else {
            completion(manualPath)
            return
        }

        UIApplication.shared.open(first, options: [:]) { opened in
            Task { @MainActor in
                if opened {
                    completion(nil)
                } else {
                    openFirstAvailable(
                        Array(urls.dropFirst()),
                        manualPath: manualPath,
                        completion: completion
                    )
                }
            }
        }
    }
}
