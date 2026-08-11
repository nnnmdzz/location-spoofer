import Foundation
import Security

struct PrivateUpdateConfiguration: Codable, Equatable {
    let workerURL: URL
    let personalToken: String
}

enum PrivateUpdateConfigurationError: LocalizedError {
    case invalidWorkerURL
    case emptyToken
    case keychain(OSStatus)
    case invalidStoredData

    var errorDescription: String? {
        switch self {
        case .invalidWorkerURL:
            return "Worker 地址必须是有效的 HTTPS 地址。"
        case .emptyToken:
            return "Signing Request Token 不能为空。"
        case .keychain(let status):
            return "无法访问私人更新钥匙串（\(status)）。"
        case .invalidStoredData:
            return "钥匙串中的私人更新配置无法解析。"
        }
    }
}

enum PrivateUpdateConfigurationStore {
    private static let service = "com.paopaolabs.location-spoofer.private-update"
    private static let account = "worker-configuration"
    static let stableAccessGroup = "4JJ849C5Q2.com.paopaolabs.location-spoofer"
    static let legacyAccessGroup = "4JJ849C5Q2.app.cauliflower3903.lemon2546"
    static let signingAccessGroups = [stableAccessGroup, legacyAccessGroup]

    static func load() throws -> PrivateUpdateConfiguration? {
        var firstAccessError: OSStatus?
        for accessGroup in [stableAccessGroup, legacyAccessGroup, nil] as [String?] {
            do {
                if let configuration = try load(accessGroup: accessGroup) {
                    if accessGroup != stableAccessGroup {
                        try saveStable(configuration: configuration)
                    }
                    return configuration
                }
            } catch PrivateUpdateConfigurationError.keychain(let status) where status == errSecMissingEntitlement {
                firstAccessError = firstAccessError ?? status
                continue
            }
        }
        if let firstAccessError { throw PrivateUpdateConfigurationError.keychain(firstAccessError) }
        return nil
    }

    private static func load(accessGroup: String?) throws -> PrivateUpdateConfiguration? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ].merging(accessGroup.map { [kSecAttrAccessGroup as String: $0] } ?? [:]) { current, _ in current }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PrivateUpdateConfigurationError.keychain(status)
        }
        guard let configuration = try? JSONDecoder().decode(PrivateUpdateConfiguration.self, from: data) else {
            throw PrivateUpdateConfigurationError.invalidStoredData
        }
        return configuration
    }

    static func save(workerURL rawWorkerURL: String, personalToken rawToken: String) throws {
        let workerURL = try validatedWorkerURL(rawWorkerURL)
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw PrivateUpdateConfigurationError.emptyToken }
        let configuration = PrivateUpdateConfiguration(workerURL: workerURL, personalToken: token)
        try save(configuration: configuration)
    }

    private static func save(configuration: PrivateUpdateConfiguration) throws {
        try saveStable(configuration: configuration)
    }

    private static func saveStable(configuration: PrivateUpdateConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessGroup as String: stableAccessGroup,
        ]
        let updateStatus = SecItemUpdate(
            matchQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PrivateUpdateConfigurationError.keychain(updateStatus)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessGroup as String: stableAccessGroup,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PrivateUpdateConfigurationError.keychain(status)
        }
    }

    static func clear() throws {
        try clear(accessGroups: [stableAccessGroup, legacyAccessGroup, nil])
    }

    private static func clear(accessGroups: [String?]) throws {
        var firstFailure: OSStatus?
        for accessGroup in accessGroups {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            ].merging(accessGroup.map { [kSecAttrAccessGroup as String: $0] } ?? [:]) { current, _ in current }
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound && status != errSecMissingEntitlement {
                firstFailure = firstFailure ?? status
            }
        }
        if let firstFailure { throw PrivateUpdateConfigurationError.keychain(firstFailure) }
    }

    private static func validatedWorkerURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else {
            throw PrivateUpdateConfigurationError.invalidWorkerURL
        }
        components.fragment = nil
        components.query = nil
        if components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else {
            throw PrivateUpdateConfigurationError.invalidWorkerURL
        }
        return url
    }
}

struct PrivateSignedUpdateStatus: Equatable {
    let requestedVersion: ForkReleaseVersion
    let bundleIdentifier: String
    let available: Bool
    let state: String?
    let manifestURL: URL?
    let expiresAt: String?
    let ipaSHA256: String?
    let errorCode: String?
    let message: String?
}

enum PrivateSignedUpdateServiceError: LocalizedError {
    case missingBundleIdentifier
    case unauthorized
    case wrongBundleIdentifier(String)
    case invalidManifestURL
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return "当前 App 没有可用的 Bundle ID，无法请求私人签名更新。"
        case .unauthorized:
            return "私人更新鉴权失败，请检查 Worker 地址和 Signing Request Token。"
        case .wrongBundleIdentifier(let bundleIdentifier):
            return "私人更新返回了不匹配的 Bundle ID：\(bundleIdentifier)。"
        case .invalidManifestURL:
            return "私人更新没有返回有效的 HTTPS OTA manifest。"
        case .network(let message):
            return "私人更新请求失败：\(message)"
        }
    }
}

enum PrivateSignedUpdateService {
    static func fetch(
        configuration: PrivateUpdateConfiguration,
        release: ForkReleaseCheckResult
    ) async throws -> PrivateSignedUpdateStatus {
        guard let currentBundleIdentifier = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !currentBundleIdentifier.isEmpty else {
            throw PrivateSignedUpdateServiceError.missingBundleIdentifier
        }
        let expectedSHA256: String? = {
            guard let digest = release.digest?.lowercased() else { return nil }
            let value = digest.hasPrefix("sha256:") ? String(digest.dropFirst(7)) : digest
            return value.count == 64 && value.allSatisfy { $0.isHexDigit } ? value : nil
        }()
        let client = PrivateSigningClient(configuration: configuration)
        let options = PrivateSigningOptions(
            signingMode: .split,
            targetBundleIdentifier: currentBundleIdentifier,
            profileID: "personal-main",
            keychainAccessGroups: PrivateUpdateConfigurationStore.signingAccessGroups,
            embeddedBundlePolicy: .stripUnsupported,
            entitlementPolicy: .stripUnsupported,
            expectedSHA256: expectedSHA256
        )
        let created: PrivateSigningJob
        do {
            created = try await client.createURLJob(sourceURL: release.ipaURL, options: options)
        } catch PrivateSigningClientError.unauthorized {
            throw PrivateSignedUpdateServiceError.unauthorized
        } catch {
            throw PrivateSignedUpdateServiceError.network(error.localizedDescription)
        }
        let job = (try? await client.job(id: created.jobID)) ?? created
        var links: PrivateSigningLinks?
        if job.status == .completed {
            links = try await client.links(jobID: job.jobID)
        }
        if let returnedBundleIdentifier = job.actualBundleIdentifier,
           returnedBundleIdentifier != currentBundleIdentifier {
            throw PrivateSignedUpdateServiceError.wrongBundleIdentifier(returnedBundleIdentifier)
        }

        return PrivateSignedUpdateStatus(
            requestedVersion: release.latestVersion,
            bundleIdentifier: job.actualBundleIdentifier ?? currentBundleIdentifier,
            available: links != nil,
            state: job.status.rawValue,
            manifestURL: links?.manifestURL,
            expiresAt: links?.expiresAt,
            ipaSHA256: job.finalSHA256,
            errorCode: job.errorCode,
            message: job.message
        )
    }

    static func installationURL(manifestURL: URL) -> URL? {
        guard manifestURL.scheme?.lowercased() == "https" else { return nil }
        var components = URLComponents()
        components.scheme = "itms-services"
        components.host = ""
        components.queryItems = [
            URLQueryItem(name: "action", value: "download-manifest"),
            URLQueryItem(name: "url", value: manifestURL.absoluteString),
        ]
        return components.url
    }
}
