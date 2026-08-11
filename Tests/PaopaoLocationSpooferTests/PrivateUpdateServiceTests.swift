import XCTest
@testable import PaopaoLocationSpoofer

final class PrivateUpdateServiceTests: XCTestCase {
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
