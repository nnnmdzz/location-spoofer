import Foundation

struct PublicReleaseCandidate: Equatable {
    let version: String
    let ipaURL: URL
    let expectedSHA256: String?
}

enum PublicReleaseSourceError: LocalizedError {
    case invalidCurrentVersion
    case invalidResponse
    case missingAsset(String)

    var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion:
            return "当前版本号格式无法比较。"
        case .invalidResponse:
            return "无法读取公开 GitHub Release。"
        case .missingAsset(let tag):
            return "Release \(tag) 没有对应的 unsigned IPA。"
        }
    }
}

/// Public unsigned-release discovery is intentionally an application concern. Private signing
/// uses the Worker's project/version registry and never consumes this URL.
struct PublicReleaseSource {
    let repository: String
    let assetNameTemplate: String
    let userAgent: String

    func latestRelease(currentVersion: String) async throws -> PublicReleaseCandidate? {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw PublicReleaseSourceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw PublicReleaseSourceError.invalidResponse
        }
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: data)
        } catch {
            throw PublicReleaseSourceError.invalidResponse
        }

        guard let current = Self.versionTuple(currentVersion),
              let latest = Self.versionTuple(release.tagName) else {
            throw PublicReleaseSourceError.invalidCurrentVersion
        }
        guard Self.compare(current, latest) == .orderedAscending else { return nil }

        let name = Self.assetName(template: assetNameTemplate, tag: release.tagName)
        guard let asset = release.assets.first(where: { $0.name == name }) else {
            throw PublicReleaseSourceError.missingAsset(release.tagName)
        }
        return PublicReleaseCandidate(
            version: release.tagName,
            ipaURL: asset.browserDownloadURL,
            expectedSHA256: Self.normalizedSHA256(asset.digest)
        )
    }

    private static func assetName(template: String, tag: String) -> String {
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return template
            .replacingOccurrences(of: "{tag}", with: tag)
            .replacingOccurrences(of: "{version}", with: version)
    }

    private static func versionTuple(_ raw: String) -> [Int]? {
        let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let halves = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard halves.count == 2,
              let build = Int(halves[1]) else { return nil }
        let dotted = halves[0].split(separator: ".")
        guard dotted.count == 3,
              let major = Int(dotted[0]),
              let minor = Int(dotted[1]),
              let patch = Int(dotted[2]) else { return nil }
        return [major, minor, patch, build]
    }

    private static func compare(_ left: [Int], _ right: [Int]) -> ComparisonResult {
        for (a, b) in zip(left, right) {
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func normalizedSHA256(_ raw: String?) -> String? {
        guard var value = raw?.lowercased() else { return nil }
        if value.hasPrefix("sha256:") { value.removeFirst(7) }
        guard value.count == 64, value.allSatisfy(\.isHexDigit) else { return nil }
        return value
    }

    private struct Release: Decodable {
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
        let assets: [Asset]

        private enum CodingKeys: String, CodingKey {
            case assets
            case tagName = "tag_name"
        }
    }
}
