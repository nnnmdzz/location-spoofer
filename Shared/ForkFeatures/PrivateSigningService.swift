import Foundation

enum PrivateSigningMode: String, Codable, CaseIterable, Identifiable {
    case split
    case standard

    var id: String { rawValue }
}

enum PrivateSigningCompatibilityPolicy: String, Codable {
    case stripUnsupported = "strip_unsupported"
    case requireAll = "require_all"
}

struct PrivateSigningOptions: Encodable, Equatable {
    var signingMode: PrivateSigningMode = .split
    var targetBundleIdentifier: String?
    var profileID: String?
    var keychainAccessGroups: [String] = []
    var embeddedBundlePolicy: PrivateSigningCompatibilityPolicy = .stripUnsupported
    var entitlementPolicy: PrivateSigningCompatibilityPolicy = .stripUnsupported
    var expectedSHA256: String?
    var expectedVersion: String?
    var expectedBuild: String?

    private enum CodingKeys: String, CodingKey {
        case signingMode = "signing_mode"
        case targetBundleIdentifier = "target_bundle_id"
        case profileID = "profile_id"
        case keychainAccessGroups = "keychain_access_groups"
        case embeddedBundlePolicy = "embedded_bundle_policy"
        case entitlementPolicy = "entitlement_policy"
        case expectedSHA256 = "expected_sha256"
        case expectedVersion = "expected_version"
        case expectedBuild = "expected_build"
    }
}

enum PrivateSigningJobStatus: Equatable, Decodable {
    case dispatching
    case queued
    case dispatchFailed
    case signing
    case following
    case completed
    case failed
    case cancelled
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = switch value {
        case "dispatching": .dispatching
        case "queued": .queued
        case "dispatch_failed": .dispatchFailed
        case "signing": .signing
        case "following": .following
        case "completed": .completed
        case "failed": .failed
        case "cancelled": .cancelled
        default: .unknown(value)
        }
    }

    var rawValue: String {
        switch self {
        case .dispatching: "dispatching"
        case .queued: "queued"
        case .dispatchFailed: "dispatch_failed"
        case .signing: "signing"
        case .following: "following"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        case .unknown(let value): value
        }
    }

    var isActive: Bool { self == .dispatching || self == .queued || self == .signing || self == .following }
    var isFailure: Bool { self == .failed || self == .dispatchFailed }
}

struct PrivateSigningJob: Decodable, Identifiable, Equatable {
    let jobID: String
    let status: PrivateSigningJobStatus
    let signingMode: PrivateSigningMode?
    let source: String?
    let createdAt: String?
    let updatedAt: String?
    let attempt: Int?
    let errorCode: String?
    let message: String?
    let actualBundleIdentifier: String?
    let actualVersion: String?
    let actualBuild: String?
    let actualTitle: String?
    let finalSHA256: String?
    let warnings: [String]?

    var id: String { jobID }
    var isActive: Bool { status.isActive }

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status, source, attempt, message, warnings
        case signingMode = "signing_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case errorCode = "error_code"
        case actualBundleIdentifier = "actual_bundle_id"
        case actualVersion = "actual_version"
        case actualBuild = "actual_build"
        case actualTitle = "actual_title"
        case finalSHA256 = "final_sha256"
    }
}

struct PrivateSigningLinks: Decodable, Equatable {
    let manifestURL: URL
    let installURL: URL
    let exportURL: URL
    let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case manifestURL = "manifest_url"
        case installURL = "install_url"
        case exportURL = "export_url"
        case expiresAt = "expires_at"
    }
}

protocol PrivateSigningTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: PrivateSigningTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

enum PrivateSigningClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case sourceTooLarge
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无法组成私人签名请求地址。"
        case .invalidResponse: return "私人签名服务返回了无法解析的数据。"
        case .unauthorized: return "Signing Request Token 不正确。"
        case .sourceTooLarge: return "IPA 超过当前 100 MB 上限。"
        case .server(let status, let message): return "私人签名服务错误（HTTP \(status)）：\(message)"
        }
    }
}

struct PrivateSigningClient {
    static let maximumSourceBytes = 100 * 1024 * 1024
    static let maximumPartBytes = 8 * 1024 * 1024

    let configuration: PrivateUpdateConfiguration
    private let transport: PrivateSigningTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(configuration: PrivateUpdateConfiguration, transport: PrivateSigningTransport? = nil) {
        self.configuration = configuration
        if let transport {
            self.transport = transport
        } else {
            let settings = URLSessionConfiguration.ephemeral
            settings.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            settings.timeoutIntervalForRequest = 30
            settings.timeoutIntervalForResource = 300
            self.transport = URLSession(configuration: settings)
        }
    }

    func createURLJob(sourceURL: URL, options: PrivateSigningOptions) async throws -> PrivateSigningJob {
        var payload = try encodedOptions(options)
        payload["source_url"] = sourceURL.absoluteString
        return try await send(path: "v2/sign/jobs", method: "POST", json: payload)
    }

    func uploadAndCreateJob(filename: String, data: Data, options: PrivateSigningOptions) async throws -> PrivateSigningJob {
        guard data.count <= Self.maximumSourceBytes else { throw PrivateSigningClientError.sourceTooLarge }
        let session: UploadSessionResponse = try await send(
            path: "v2/uploads",
            method: "POST",
            json: ["filename": filename, "size": data.count]
        )
        let partSize = try validatedPartSize(session.partSize)
        var offset = 0
        var partNumber = 1
        while offset < data.count {
            let end = min(offset + partSize, data.count)
            try await uploadPart(
                uploadID: session.uploadID,
                partNumber: partNumber,
                data: data.subdata(in: offset..<end)
            )
            offset = end
            partNumber += 1
        }
        try await completeUpload(uploadID: session.uploadID)
        var payload = try encodedOptions(options)
        payload["upload_id"] = session.uploadID
        return try await send(path: "v2/sign/jobs", method: "POST", json: payload)
    }

    func uploadAndCreateJob(fileURL: URL, options: PrivateSigningOptions) async throws -> PrivateSigningJob {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        guard let size = values.fileSize, size > 0, size <= Self.maximumSourceBytes else {
            throw PrivateSigningClientError.sourceTooLarge
        }
        let session: UploadSessionResponse = try await send(
            path: "v2/uploads",
            method: "POST",
            json: ["filename": values.name ?? fileURL.lastPathComponent, "size": size]
        )
        let partSize = try validatedPartSize(session.partSize)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var partNumber = 1
        while true {
            let part = try handle.read(upToCount: partSize) ?? Data()
            if part.isEmpty { break }
            try await uploadPart(uploadID: session.uploadID, partNumber: partNumber, data: part)
            partNumber += 1
        }
        try await completeUpload(uploadID: session.uploadID)
        var payload = try encodedOptions(options)
        payload["upload_id"] = session.uploadID
        return try await send(path: "v2/sign/jobs", method: "POST", json: payload)
    }

    func job(id: String) async throws -> PrivateSigningJob {
        try await send(path: "v2/sign/jobs/\(id)", method: "GET")
    }

    func history() async throws -> [PrivateSigningJob] {
        var jobs: [PrivateSigningJob] = []
        var cursor: String?
        var seenCursors = Set<String>()
        repeat {
            let queryItems = cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
            let response: JobHistoryResponse = try await send(
                path: "v2/sign/jobs",
                method: "GET",
                queryItems: queryItems
            )
            jobs.append(contentsOf: response.jobs)
            cursor = response.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw PrivateSigningClientError.invalidResponse
            }
            if seenCursors.count > 300 {
                throw PrivateSigningClientError.invalidResponse
            }
        } while cursor != nil
        return jobs
    }

    func retry(jobID: String) async throws -> PrivateSigningJob {
        try await send(path: "v2/sign/jobs/\(jobID)/retry", method: "POST", json: [:])
    }

    func cancel(jobID: String) async throws -> PrivateSigningJob {
        try await send(path: "v2/sign/jobs/\(jobID)/cancel", method: "POST", json: [:])
    }

    func links(jobID: String) async throws -> PrivateSigningLinks {
        try await send(path: "v2/sign/jobs/\(jobID)/links", method: "POST", json: [:])
    }

    private func validatedPartSize(_ value: Int) throws -> Int {
        guard value > 0, value <= Self.maximumPartBytes else {
            throw PrivateSigningClientError.invalidResponse
        }
        return value
    }

    private func uploadPart(uploadID: String, partNumber: Int, data: Data) async throws {
        var request = try authorizedRequest(path: "v2/uploads/\(uploadID)/parts/\(partNumber)", method: "PUT")
        request.httpBody = data
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let _: UploadPartResponse = try await perform(request)
    }

    private func completeUpload(uploadID: String) async throws {
        let _: UploadCompleteResponse = try await send(
            path: "v2/uploads/\(uploadID)/complete",
            method: "POST",
            json: [:]
        )
    }

    private func encodedOptions(_ options: PrivateSigningOptions) throws -> [String: Any] {
        let data = try encoder.encode(options)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PrivateSigningClientError.invalidResponse
        }
        return value
    }

    private func send<T: Decodable>(
        path: String,
        method: String,
        json: [String: Any]? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var request = try authorizedRequest(path: path, method: method, queryItems: queryItems)
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request)
    }

    private func authorizedRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let segments = path.split(separator: "/").map(String.init)
        let baseURL = segments.reduce(configuration.workerURL) { partial, segment in
            partial.appendingPathComponent(segment)
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw PrivateSigningClientError.invalidURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw PrivateSigningClientError.invalidURL }
        guard url.scheme?.lowercased() == "https" else { throw PrivateSigningClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(configuration.personalToken)", forHTTPHeaderField: "Authorization")
        request.setValue("Location-Spoofer/\(ForkReleaseService.currentVersionString)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PrivateSigningClientError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw PrivateSigningClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let message = payload?["message"] as? String ?? payload?["error"] as? String ?? "未知错误"
            throw PrivateSigningClientError.server(http.statusCode, message)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PrivateSigningClientError.invalidResponse
        }
    }
}

private struct UploadSessionResponse: Decodable {
    let uploadID: String
    let partSize: Int

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case partSize = "part_size"
    }
}

private struct UploadPartResponse: Decodable {
    let uploadID: String
    let partNumber: Int

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case partNumber = "part_number"
    }
}

private struct UploadCompleteResponse: Decodable {
    let uploadID: String
    let status: String

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case status
    }
}

private struct JobHistoryResponse: Decodable {
    let jobs: [PrivateSigningJob]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case jobs
        case nextCursor = "next_cursor"
    }
}
