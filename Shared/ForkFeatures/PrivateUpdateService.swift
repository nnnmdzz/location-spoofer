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
            return "Personal Update Token 不能为空。"
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

    static func load() throws -> PrivateUpdateConfiguration? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
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
        let data = try JSONEncoder().encode(configuration)
        try clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PrivateUpdateConfigurationError.keychain(status)
        }
    }

    static func clear() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PrivateUpdateConfigurationError.keychain(status)
        }
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
    case invalidRequestURL
    case missingBundleIdentifier
    case invalidResponse
    case unauthorized
    case unavailable(Int)
    case wrongVersion(String)
    case wrongBundleIdentifier(String)
    case invalidManifestURL
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequestURL:
            return "私人更新 Worker 地址无法组成有效请求。"
        case .missingBundleIdentifier:
            return "当前 App 没有可用的 Bundle ID，无法请求私人签名更新。"
        case .invalidResponse:
            return "私人更新 Worker 返回了无法识别的数据。"
        case .unauthorized:
            return "私人更新鉴权失败，请检查 Worker 地址和 Personal Update Token。"
        case .unavailable(let status):
            return "私人更新服务暂不可用（HTTP \(status)）。"
        case .wrongVersion(let tag):
            return "私人更新返回了不匹配的版本：\(tag)。"
        case .wrongBundleIdentifier(let bundleIdentifier):
            return "私人更新返回了不匹配的 Bundle ID：\(bundleIdentifier)。"
        case .invalidManifestURL:
            return "私人更新没有返回有效的 HTTPS OTA manifest。"
        case .network(let message):
            return "私人更新请求失败：\(message)"
        }
    }
}

private struct PrivateSignedUpdateResponse: Decodable {
    let available: Bool
    let tag: String?
    let bundleIdentifier: String?
    let state: String?
    let manifestURL: URL?
    let expiresAt: String?
    let ipaSHA256: String?
    let errorCode: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case available, tag, state, message
        case bundleIdentifier = "bundle_id"
        case manifestURL = "manifest_url"
        case expiresAt = "expires_at"
        case ipaSHA256 = "ipa_sha256"
        case errorCode = "error_code"
    }
}

enum PrivateSignedUpdateService {
    static func requestURL(
        configuration: PrivateUpdateConfiguration,
        requestedVersion: ForkReleaseVersion,
        bundleIdentifier: String
    ) throws -> URL {
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleIdentifier.isEmpty else {
            throw PrivateSignedUpdateServiceError.missingBundleIdentifier
        }
        let endpoint = configuration.workerURL
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("location-spoofer", isDirectory: true)
            .appendingPathComponent("update", isDirectory: false)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw PrivateSignedUpdateServiceError.invalidRequestURL
        }
        components.queryItems = [
            URLQueryItem(name: "tag", value: requestedVersion.tagName),
            URLQueryItem(name: "bundle_id", value: normalizedBundleIdentifier),
        ]
        guard let url = components.url else {
            throw PrivateSignedUpdateServiceError.invalidRequestURL
        }
        return url
    }

    static func fetch(
        configuration: PrivateUpdateConfiguration,
        requestedVersion: ForkReleaseVersion
    ) async throws -> PrivateSignedUpdateStatus {
        guard let currentBundleIdentifier = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !currentBundleIdentifier.isEmpty else {
            throw PrivateSignedUpdateServiceError.missingBundleIdentifier
        }
        let url = try requestURL(
            configuration: configuration,
            requestedVersion: requestedVersion,
            bundleIdentifier: currentBundleIdentifier
        )

        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        sessionConfiguration.timeoutIntervalForRequest = 8
        sessionConfiguration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.personalToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Location-Spoofer/\(ForkReleaseService.currentVersionString)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw PrivateSignedUpdateServiceError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw PrivateSignedUpdateServiceError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw PrivateSignedUpdateServiceError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw PrivateSignedUpdateServiceError.unavailable(http.statusCode)
        }
        guard let payload = try? JSONDecoder().decode(PrivateSignedUpdateResponse.self, from: data) else {
            throw PrivateSignedUpdateServiceError.invalidResponse
        }

        if let tag = payload.tag, tag != requestedVersion.tagName {
            throw PrivateSignedUpdateServiceError.wrongVersion(tag)
        }
        if let returnedBundleIdentifier = payload.bundleIdentifier,
           returnedBundleIdentifier != currentBundleIdentifier {
            throw PrivateSignedUpdateServiceError.wrongBundleIdentifier(returnedBundleIdentifier)
        }

        if payload.available {
            guard payload.tag == requestedVersion.tagName else {
                throw PrivateSignedUpdateServiceError.wrongVersion(payload.tag ?? "未知")
            }
            guard payload.bundleIdentifier == currentBundleIdentifier else {
                throw PrivateSignedUpdateServiceError.wrongBundleIdentifier(payload.bundleIdentifier ?? "未知")
            }
            guard let manifestURL = payload.manifestURL,
                  manifestURL.scheme?.lowercased() == "https" else {
                throw PrivateSignedUpdateServiceError.invalidManifestURL
            }
        }

        return PrivateSignedUpdateStatus(
            requestedVersion: requestedVersion,
            bundleIdentifier: payload.bundleIdentifier ?? currentBundleIdentifier,
            available: payload.available,
            state: payload.state,
            manifestURL: payload.manifestURL,
            expiresAt: payload.expiresAt,
            ipaSHA256: payload.ipaSHA256,
            errorCode: payload.errorCode,
            message: payload.message
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
