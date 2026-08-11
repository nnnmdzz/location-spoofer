import XCTest
@testable import PaopaoLocationSpoofer

final class ThirdPartyCommunityPromptPreferencesTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        suites.removeAll()
        super.tearDown()
    }

    func testSuppressionBecomesAvailableOnThirdPresentation() {
        let preferences = ThirdPartyCommunityPromptPreferences(defaults: makeDefaults())

        XCTAssertEqual(preferences.recordPresentation(), 1)
        XCTAssertFalse(preferences.canSuppress())
        XCTAssertEqual(preferences.recordPresentation(), 2)
        XCTAssertFalse(preferences.canSuppress())
        XCTAssertEqual(preferences.recordPresentation(), 3)
        XCTAssertTrue(preferences.canSuppress())
    }

    func testEarlySuppressionIsIgnoredAndThirdPresentationCanPersistIt() {
        let defaults = makeDefaults()
        let preferences = ThirdPartyCommunityPromptPreferences(defaults: defaults)

        preferences.recordPresentation()
        preferences.suppress()
        XCTAssertTrue(preferences.shouldPresent())

        preferences.recordPresentation()
        preferences.recordPresentation()
        preferences.suppress()
        XCTAssertFalse(preferences.shouldPresent())

        let restored = ThirdPartyCommunityPromptPreferences(defaults: defaults)
        XCTAssertFalse(restored.shouldPresent())
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ThirdPartyCommunityPromptPreferencesTests.\(UUID().uuidString)"
        suites.append(suite)
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
