import Foundation
import PrivateSignerKit
import PrivateSignerSelfUpdate
import PrivateSignerUI

/// Everything specific to this app's private-signing integration.
///
/// Only stable application identity belongs here. Profile IDs, release URLs, and latest-version
/// policy are Worker deployment state and are discovered at runtime through the v2 SDK.
enum PrivateSigning {
    static let teamID = "4JJ849C5Q2"

    /// The Stable Configuration Group. Changing this value strands the Worker URL and token of
    /// every installed client; move the old value into `legacyAccessGroups` instead.
    static let configurationAccessGroup = "\(teamID).com.paopaolabs.location-spoofer"

    /// Written by builds up to `1.0.5-0005`.
    static let legacyAccessGroups = ["\(teamID).app.cauliflower3903.lemon2546"]

    static let keychainService = "com.paopaolabs.location-spoofer.private-update"

    /// Stable identity understood by the Worker's project registry.
    static let projectID = "location-spoofer"
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

    static var coordinator: SelfUpdateCoordinator {
        SelfUpdateCoordinator(
            store: store,
            projectID: projectID,
            currentVersion: currentVersionString,
            userAgent: userAgent,
            installedBundleIdentifier: installedBundleIdentifier
        )
    }

    static var uiContext: SignerUIContext {
        SignerUIContext(
            keychain: keychain,
            userAgent: userAgent
        )
    }
}

/// This remains solely for the public unsigned-IPA copy workflow. It is deliberately not used by
/// private signing or self-update.
enum PublicUpdate {
    static let source = PublicReleaseSource(
        repository: "nnnmdzz/location-spoofer",
        assetNameTemplate: "Location-Spoofer-{tag}-unsigned.ipa",
        userAgent: PrivateSigning.userAgent
    )
}
