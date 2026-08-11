import XCTest
@testable import PaopaoLocationSpoofer

@MainActor
final class ThirdPartyModuleSourceStoreTests: XCTestCase {
    func testMirrorDefaultsToEnabledAndPersists() {
        let suite = "ThirdPartyModuleSourceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ThirdPartyModuleSourceStore(defaults: defaults)
        XCTAssertTrue(store.useMirror)

        store.setUseMirror(false)
        XCTAssertFalse(ThirdPartyModuleSourceStore(defaults: defaults).useMirror)
    }
}
