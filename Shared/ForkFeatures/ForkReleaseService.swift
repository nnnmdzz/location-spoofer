import Foundation

struct ForkReleaseVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let sequence: Int

    init?(_ rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("v") { value.removeFirst() }
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[1].count == 4,
              parts[1].allSatisfy({ $0.isNumber }),
              let sequence = Int(parts[1]) else { return nil }
        let base = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard base.count == 3,
              let major = Int(base[0]), major >= 0,
              let minor = Int(base[1]), minor >= 0,
              let patch = Int(base[2]), patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.sequence = sequence
    }

    var description: String {
        String(format: "%d.%d.%d-%04d", major, minor, patch, sequence)
    }

    var tagName: String { "v\(description)" }

    static func < (lhs: ForkReleaseVersion, rhs: ForkReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch, lhs.sequence) <
            (rhs.major, rhs.minor, rhs.patch, rhs.sequence)
    }
}

struct ForkReleaseCheckResult: Equatable {
    let currentVersion: ForkReleaseVersion
    let latestVersion: ForkReleaseVersion
    let ipaURL: URL
    let digest: String?

    var updateAvailable: Bool { currentVersion < latestVersion }
}

enum ForkReleaseServiceError: LocalizedError, Equatable {
    case invalidCurrentVersion(String)
    case invalidResponse
    case noValidRelease
    case missingIPA(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion(let version):
            return "当前 Fork 版本号无效：\(version)"
        case .invalidResponse:
            return "GitHub Releases 返回了无法识别的数据"
        case .noValidRelease:
            return "没有找到符合 vX.Y.Z-NNNN 格式的正式 Release"
        case .missingIPA(let tag):
            return "Release \(tag) 打包不完整，未找到 IPA"
        case .network(let message):
            return "检查更新失败：\(message)"
        }
    }
}

private struct ForkGitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        private enum CodingKeys: String, CodingKey {
            case name, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name"
    }
}

enum ForkReleaseService {
    static let repository = "nnnmdzz/location-spoofer"
    static let releasesAPI = URL(string: "https://api.github.com/repos/nnnmdzz/location-spoofer/releases?per_page=30")!
    static let bundledFallbackVersion = "1.0.5-0001"

    static var currentVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "ForkReleaseVersion") as? String
            ?? bundledFallbackVersion
    }

    static func fetchLatest() async throws -> ForkReleaseCheckResult {
        let currentString = currentVersionString
        guard let current = ForkReleaseVersion(currentString) else {
            throw ForkReleaseServiceError.invalidCurrentVersion(currentString)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Location-Spoofer/\(current.description)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ForkReleaseServiceError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ForkReleaseServiceError.invalidResponse
        }
        let releases: [ForkGitHubRelease]
        do {
            releases = try JSONDecoder().decode([ForkGitHubRelease].self, from: data)
        } catch {
            throw ForkReleaseServiceError.invalidResponse
        }

        let candidates = releases.compactMap { release -> (ForkReleaseVersion, ForkGitHubRelease)? in
            guard !release.draft,
                  !release.prerelease,
                  let version = ForkReleaseVersion(release.tagName) else { return nil }
            return (version, release)
        }
        guard let latest = candidates.max(by: { $0.0 < $1.0 }) else {
            throw ForkReleaseServiceError.noValidRelease
        }

        let expectedAssetName = "Location-Spoofer-\(latest.0.tagName)-unsigned.ipa"
        guard let asset = latest.1.assets.first(where: { $0.name == expectedAssetName }) else {
            throw ForkReleaseServiceError.missingIPA(latest.0.tagName)
        }

        return ForkReleaseCheckResult(
            currentVersion: current,
            latestVersion: latest.0,
            ipaURL: asset.browserDownloadURL,
            digest: asset.digest
        )
    }
}