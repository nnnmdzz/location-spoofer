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
