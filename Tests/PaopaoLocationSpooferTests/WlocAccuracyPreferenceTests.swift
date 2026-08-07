import XCTest
@testable import PaopaoLocationSpoofer

@MainActor
final class WlocAccuracyPreferenceTests: XCTestCase {
    func testDefaultsToUpstreamStandardAccuracy() {
        let defaults = makeDefaults()
        let preference = WlocAccuracyPreference(defaults: defaults)

        XCTAssertEqual(preference.meters, 25)
        XCTAssertEqual(preference.matchingPreset, .standard)
        XCTAssertFalse(preference.isCustom)
    }

    func testPresetPersists() {
        let defaults = makeDefaults()
        let preference = WlocAccuracyPreference(defaults: defaults)

        preference.select(.high)

        XCTAssertEqual(preference.meters, 5)
        XCTAssertEqual(WlocAccuracyPreference(defaults: defaults).meters, 5)
    }

    func testCustomAccuracyPersistsAndIsReportedAsCustom() {
        let defaults = makeDefaults()
        let preference = WlocAccuracyPreference(defaults: defaults)

        XCTAssertTrue(preference.setCustomMeters(7))
        XCTAssertEqual(preference.meters, 7)
        XCTAssertNil(preference.matchingPreset)
        XCTAssertTrue(preference.isCustom)
        XCTAssertEqual(WlocAccuracyPreference(defaults: defaults).meters, 7)
    }

    func testRejectsOutOfRangeCustomAccuracy() {
        let defaults = makeDefaults()
        let preference = WlocAccuracyPreference(defaults: defaults)

        XCTAssertFalse(preference.setCustomMeters(0))
        XCTAssertFalse(preference.setCustomMeters(1001))
        XCTAssertEqual(preference.meters, 25)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WlocAccuracyPreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
