import XCTest
@testable import PaopaoLocationSpoofer

final class PrivateUpdateServiceTests: XCTestCase {
    func testRequestURLIncludesReleaseTagAndInstalledBundleIdentifier() throws {
        let configuration = PrivateUpdateConfiguration(
            workerURL: URL(string: "https://signer.example.com")!,
            personalToken: "token"
        )
        let version = ForkReleaseVersion("1.2.3-0042")!

        let url = try PrivateSignedUpdateService.requestURL(
            configuration: configuration,
            requestedVersion: version,
            bundleIdentifier: "com.nnnmdzz.location"
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(url.path, "/v1/location-spoofer/update")
        XCTAssertEqual(query["tag"], "v1.2.3-0042")
        XCTAssertEqual(query["bundle_id"], "com.nnnmdzz.location")
    }

    func testRequestURLRejectsEmptyBundleIdentifier() throws {
        let configuration = PrivateUpdateConfiguration(
            workerURL: URL(string: "https://signer.example.com")!,
            personalToken: "token"
        )
        let version = ForkReleaseVersion("1.2.3-0042")!

        XCTAssertThrowsError(
            try PrivateSignedUpdateService.requestURL(
                configuration: configuration,
                requestedVersion: version,
                bundleIdentifier: "   "
            )
        ) { error in
            guard case PrivateSignedUpdateServiceError.missingBundleIdentifier = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testInstallationURLWrapsHTTPSManifest() throws {
        let manifest = URL(string: "https://signer.example.com/v1/ota/manifest?token=abc")!
        let install = try XCTUnwrap(PrivateSignedUpdateService.installationURL(manifestURL: manifest))
        let components = URLComponents(url: install, resolvingAgainstBaseURL: false)
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components?.scheme, "itms-services")
        XCTAssertEqual(query["action"], "download-manifest")
        XCTAssertEqual(query["url"], manifest.absoluteString)
    }
}
