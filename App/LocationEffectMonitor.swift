import Combine
import CoreLocation
import Foundation

enum LocationEffectStatus: Equatable {
    case idle
    case refreshing(attempt: Int, total: Int)
    case effective(distanceMeters: Double, accuracyMeters: Double)
    case cachePending(distanceMeters: Double, accuracyMeters: Double)
    case gpsLikelyDominant(distanceMeters: Double, accuracyMeters: Double)
    case unavailable

    var diagnosticName: String {
        switch self {
        case .idle: return "idle"
        case .refreshing: return "refreshing"
        case .effective: return "effective"
        case .cachePending: return "cachePending"
        case .gpsLikelyDominant: return "gpsLikelyDominant"
        case .unavailable: return "unavailable"
        }
    }
}

enum LocationEffectEvaluator {
    static func evaluate(
        target: CLLocationCoordinate2D,
        sample: CLLocation,
        previousSample: CLLocation?,
        previousTarget: CLLocationCoordinate2D? = nil
    ) -> LocationEffectStatus {
        let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
        let distance = sample.distance(from: targetLocation)
        let accuracy = max(0, sample.horizontalAccuracy)
        let effectiveRadius = max(120, min(400, accuracy * 4))

        if distance <= effectiveRadius {
            return .effective(distanceMeters: distance, accuracyMeters: accuracy)
        }

        if let previousTarget {
            let oldTargetLocation = CLLocation(
                latitude: previousTarget.latitude,
                longitude: previousTarget.longitude
            )
            let oldTargetRadius = max(150, min(500, accuracy * 5))
            if sample.distance(from: oldTargetLocation) <= oldTargetRadius {
                return .cachePending(distanceMeters: distance, accuracyMeters: accuracy)
            }
        }

        let clearlyFar = distance >= max(500, effectiveRadius * 2)
        let highPrecision = accuracy <= 35
        let nearPreviousPhysicalSample: Bool = {
            guard previousTarget == nil, let previousSample else { return false }
            let previousAccuracy = max(0, previousSample.horizontalAccuracy)
            let radius = max(120, max(accuracy, previousAccuracy) * 4)
            return sample.distance(from: previousSample) <= radius
        }()

        if clearlyFar && (highPrecision || (nearPreviousPhysicalSample && accuracy <= 80)) {
            return .gpsLikelyDominant(distanceMeters: distance, accuracyMeters: accuracy)
        }

        return .cachePending(distanceMeters: distance, accuracyMeters: accuracy)
    }
}

@MainActor
final class LocationEffectMonitor: ObservableObject {
    static let shared = LocationEffectMonitor()

    @Published private(set) var status: LocationEffectStatus = .idle
    @Published private(set) var target: CLLocationCoordinate2D?

    private let realtime: RealtimeLocationManager
    private var previousSample: CLLocation?
    private var previousTarget: CLLocationCoordinate2D?
    private var verificationTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    private let automaticAttemptCount = 3
    private let automaticAttemptIntervalNanoseconds: UInt64 = 10_000_000_000

    init(realtime: RealtimeLocationManager = .shared) {
        self.realtime = realtime
    }

    func activate(target newTarget: CLLocationCoordinate2D, previousSample: CLLocation? = nil) {
        previousTarget = target.flatMap { oldTarget in
            Self.coordinatesMatch(oldTarget, newTarget) ? nil : oldTarget
        }
        target = newTarget
        self.previousSample = previousSample ?? realtime.location
        startAutomaticVerification(reason: "虚拟定位写入完成")
    }

    func restoreActiveTarget(_ restoredTarget: CLLocationCoordinate2D) {
        if let currentTarget = target, Self.coordinatesMatch(currentTarget, restoredTarget) {
            return
        }
        previousTarget = target
        target = restoredTarget
        previousSample = realtime.location
        startAutomaticVerification(reason: "恢复已持久化目标")
    }

    func retry(reason: String = "用户重新检测") {
        guard target != nil else { return }
        startVerification(
            reason: reason,
            attemptCount: 1,
            intervalNanoseconds: 0
        )
    }

    func clear() {
        generation &+= 1
        verificationTask?.cancel()
        verificationTask = nil
        target = nil
        previousTarget = nil
        previousSample = nil
        status = .idle
        RuntimeLogger.info("APP", "定位生效检测", "已清除生效检测状态")
    }

    private func startAutomaticVerification(reason: String) {
        startVerification(
            reason: reason,
            attemptCount: automaticAttemptCount,
            intervalNanoseconds: automaticAttemptIntervalNanoseconds
        )
    }

    private func startVerification(
        reason: String,
        attemptCount: Int,
        intervalNanoseconds: UInt64
    ) {
        guard let target else { return }
        generation &+= 1
        let currentGeneration = generation
        verificationTask?.cancel()
        verificationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            RuntimeLogger.info("APP", "定位生效检测", "开始软刷新与生效检测", details: [
                "原因": reason,
                "目标纬度": String(format: "%.8f", target.latitude),
                "目标经度": String(format: "%.8f", target.longitude),
                "有上一虚拟目标": String(self.previousTarget != nil),
                "请求精度": "100m",
                "检测次数": String(attemptCount),
                "检测间隔秒": intervalNanoseconds == 0 ? "0" : "10"
            ])

            var lastStatus: LocationEffectStatus = .unavailable
            var receivedSample = false
            let seriesStartedAt = Date()
            let intervalSeconds = Double(intervalNanoseconds) / 1_000_000_000

            for attempt in 1...attemptCount {
                if attempt > 1, intervalNanoseconds > 0 {
                    let scheduledAt = seriesStartedAt.addingTimeInterval(
                        intervalSeconds * Double(attempt - 1)
                    )
                    let remaining = scheduledAt.timeIntervalSinceNow
                    if remaining > 0 {
                        do {
                            try await Task.sleep(
                                nanoseconds: UInt64(remaining * 1_000_000_000)
                            )
                        } catch {
                            return
                        }
                    }
                }

                guard !Task.isCancelled, currentGeneration == self.generation else { return }
                self.status = .refreshing(attempt: attempt, total: attemptCount)

                guard let sample = await self.realtime.requestFreshLocation(
                    desiredAccuracy: kCLLocationAccuracyHundredMeters
                ) else {
                    RuntimeLogger.warning("APP", "定位生效检测", "本轮软刷新未获取到新样本", details: [
                        "attempt": String(attempt),
                        "total": String(attemptCount)
                    ])
                    continue
                }

                receivedSample = true
                lastStatus = LocationEffectEvaluator.evaluate(
                    target: target,
                    sample: sample,
                    previousSample: self.previousSample,
                    previousTarget: self.previousTarget
                )
                self.status = lastStatus

                let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
                RuntimeLogger.info("APP", "定位生效检测", "收到软刷新样本", details: [
                    "attempt": String(attempt),
                    "total": String(attemptCount),
                    "判定": lastStatus.diagnosticName,
                    "距目标米": String(format: "%.1f", sample.distance(from: targetLocation)),
                    "horizontalAccuracy": String(format: "%.1f", sample.horizontalAccuracy),
                    "样本时间": ISO8601DateFormatter().string(from: sample.timestamp)
                ])

                if case .effective = lastStatus {
                    return
                }
            }

            guard !Task.isCancelled, currentGeneration == self.generation else { return }
            self.status = receivedSample ? lastStatus : .unavailable
        }
    }

    private static func coordinatesMatch(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) <= 0.000_001
            && abs(lhs.longitude - rhs.longitude) <= 0.000_001
    }
}
