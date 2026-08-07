import Foundation
import UIKit

enum SystemSettingsDestination {
    case appPermissions
    case general
    case wifi
    case locationServices

    var preferredURL: URL? {
        let value: String
        switch self {
        case .appPermissions:
            value = UIApplication.openSettingsURLString
        case .general:
            value = "App-Prefs:General"
        case .wifi:
            value = "App