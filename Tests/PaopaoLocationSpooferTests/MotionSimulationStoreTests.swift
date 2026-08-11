import XCTest
@testable import PaopaoLocationSpoofer

@MainActor
final class MotionSimulationStoreTests: XCTestCase {
    func testDefaultsToDisabledAndPersistsChanges() {
        let suite = "MotionSimulationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = MotionSimulationStore(defaults: defaults)
        XCTAssertFalse(store.isEnabled)

        store.setEnabled(true)
        XCTAssertTrue(MotionSimulationStore(defaults: defaults).isEnabled)
    }
}
