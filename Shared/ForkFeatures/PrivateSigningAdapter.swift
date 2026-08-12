import Foundation
import PrivateSignerKit
import PrivateSignerSelfUpdate
import PrivateSignerUI

/// Every value that is specific to *this* app's private signing setup.
///
/// The signing client itself lives in the `private-signer-ios` package. Keeping the
/// application-specific values in one file is what lets that package be upgraded without
/// touching the rest of the fork, and what keeps the fork's merge surface against upstream small.
///
/// Integration guide:
/// https://github.com/nnnmdzz/private-signer-ios/blob/main/docs/client-integration-guide.zh-CN.md
enum PrivateSigning {
    /// Public information — it is visible in any signed IPA and is the prefix of the access
    /// groups below. It is not a credential.
    static let teamID = "4JJ849C5Q2"

    /// The Stable Configuration Group. Changing this value strands the Worker URL and token of
    /// every installed client; move the old value into `legacyAccessGroups` instead.
    static let configurationAccessGroup = "\(teamID).com.paopaolabs.location-spoofer"

    /// Written by builds up to `1.0.5-0005`.
    static let legacyAccessGroups = ["\(teamID).app.cauliflower3903.lemon2546"]

    /// Unchanged from the pre-package client so already-stored configuration stays readable.
    static let keychainService = "com.paopaolabs.location-spoofer.private-update"

    static let repository = "nnnmdzz/location-spoofer"
    static let assetNameTemplate = "Location-Spoofer-{tag}-unsigned.ipa"
    static let profileID = "personal-main"
    static let bundledFallbackVersion = "1.0.5-0001"

    static var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "ForkReleaseVersion") as? String
            ?? bundledFallbackVersion
    }

    static var userAgent: String { "Location-Spoofer/\(currentVersionString)" }

    static var installedBundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.paopaolabs.location-spoofer"
    }

    static var keychain: SignerKeychainConfiguration {
        SignerKeychainConfiguration(
            service: keychainService,
            configurationAccessGroup: configurationAccessGroup,
            legacyAccessGroups: legacyAccessGroups
        )
    }

    static var store: SignerConfigurationStore {
        SignerConfigurationStore(keychain: keychain)
    }

    static var releaseSource: GitHubReleaseSource {
        GitHubReleaseSource(
            repository: repository,
            assetNameTemplate: assetNameTemplate,
            userAgent: userAgent
        )
    }

    static var coordinator: SelfUpdateCoordinator {
        SelfUpdateCoordinator(
            store: store,
            releaseSource: releaseSource,
            currentVersion: currentVersionString,
            userAgent: userAgent,
            installedBundleIdentifier: installedBundleIdentifier,
            profileID: profileID
        )
    }

    static var uiContext: SignerUIContext {
        SignerUIContext(
            keychain: keychain,
            userAgent: userAgent,
            defaultProfileID: profileID
        )
    }
}
