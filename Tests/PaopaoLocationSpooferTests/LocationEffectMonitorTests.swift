import CoreLocation
import XCTest
@testable import PaopaoLocationSpoofer

final class LocationEffectMonitorTests: XCTestCase {
    func testSampleNearTargetIsEffective() {
        let target = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
        let sample = CLLocation(
            coordinate: .init(latitude: 35.681300, longitude: 139.767100),
            altitude: 0,
            horizontalAccuracy: 60,
            verticalAccuracy: 10,
            timestamp: Date()
        )

        let result = LocationEffectEvaluator.evaluate(
            target: target,
            sample: sample,
            previousSample: nil
        )

        guard case .effective(let distance, let accuracy) = result else {
            return XCTFail("expected effective, got \(result)")
        }
        XCTAssertLessThan(distance, 120)
        XCTAssertEqual(accuracy, 60, accuracy: 0.001)
    }

    func testFarHighPrecisionSampleIsLikelyGPSDominant() {
        let target = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
        let sample = CLLocation(
            coordinate: .init(latitude: 22.543096, longitude: 114.057865),
            altitude: 0,
            horizontalAccuracy: 6,
            verticalAccuracy: 10,
            timestamp: Date()
        )

        let result = LocationEffectEvaluator.evaluate(
            target: target,
            sample: sample,
            previousSample: nil
        )

        guard case .gpsLikelyDominant(let distance, let accuracy) = result else {
            return XCTFail("expected gpsLikelyDominant, got \(result)")
        }
        XCTAssertGreaterThan(distance, 500)
        XCTAssertEqual(accuracy, 6, accuracy: 0.001)
    }

    func testFarCoarseSampleIsClassifiedAsCachePending() {
        let target = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
        let sample = CLLocation(
            coordinate: .init(latitude: 22.543096, longitude: 114.057865),
            altitude: 0,
            horizontalAccuracy: 300,
            verticalAccuracy: 100,
            timestamp: Date()
        )

        let result = LocationEffectEvaluator.evaluate(
            target: target,
            sample: sample,
            previousSample: nil
        )

        guard case .cachePending(let distance, let accuracy) = result else {
            return XCTFail("expected cachePending, got \(result)")
        }
        XCTAssertGreaterThan(distance, 500)
        XCTAssertEqual(accuracy, 300, accuracy: 0.001)
    }

    func testSampleRemainingNearPreviousPreciseLocationIsLikelyGPSDominant() {
        let target = CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125)
        let previous = CLLocation(
            coordinate: .init(latitude: 22.543096, longitude: 114.057865),
            altitude: 0,
            horizontalAccuracy: 25,
            verticalAccuracy: 10,
            timestamp: Date(timeIntervalSinceNow: -2)
        )
        let sample = CLLocation(
            coordinate: .init(latitude: 22.543200, longitude: 114.057900),
            altitude: 0,
            horizontalAccuracy: 55,
            verticalAccuracy: 10,
            timestamp: Date()
        )

        let result = LocationEffectEvaluator.evaluate(
            target: target,
            sample: sample,
            previousSample: previous
        )

        guard case .gpsLikelyDominant = result else {
            return XCTFail("expected gpsLikelyDominant, got \(result)")
        }
    }
}
