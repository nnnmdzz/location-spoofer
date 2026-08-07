import Combine
import CoreLocation
import Foundation
import UIKit

enum LocationEffectStatus: Equatable {
    case idle
    case refreshing(attempt: Int)
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
        previousSample: CLLocation?
    ) -> LocationEffectStatus {
        let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
        let distance = sample.distance(from: targetLocation)
        let accuracy = max(0, sample.horizontalAccuracy)
        let effectiveRadius = max(120, min(400, accuracy * 4))

        if distance <= effectiveRadius {
            return .effective(distanceMeters: distance, accuracyMeters: accuracy)
        }

        let clearlyFar = distance >= max(500, effectiveRadius * 2)
        let highPrecision = accuracy <= 35
        let nearPrevious: Bool = {
            guard let previousSample else { return false }
            let previousAccuracy = max(0, previousSample.horizontalAccuracy)
            let radius = max(120, max(accuracy, previousAccuracy) * 4)
            return sample.distance(from: previousSample) <= radius
        }()

        // WLOC only changes network location. A fresh, high-precision sample far
        // from the target strongly suggests that GNSS or another precise source
        // is still winning the Core Location fusion. This is deliberately a
        // heuristic: the UI must present it as "likely", never as certainty.
        if clearlyFar && (highPrecision || (nearPrevious && accuracy <= 80)) {
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
    private var verificationTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var foregroundObserver: NSObjectProtocol?

    init(realtime: RealtimeLocationManager = .shared) {
        self.realtime = realtime
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.target != nil else { return }
                switch self.status {
                case .idle, .refreshing, .effective:
                    break
                case .cachePending, .gpsLikelyDominant, .unavailable:
                    self.retry(reason: "App回到前台")
                }
            }
        }
    }

    func activate(target: CLLocationCoordinate2D, previousSample: CLLocation? = nil) {
        self.target = target
        self.previousSample = previousSample ?? realtime.location
        startVerification(reason: "虚拟定位写入完成")
    }

    func restoreActiveTarget(_ target: CLLocationCoordinate2D) {
        guard self.target == nil else { return }
        self.target = target
        previousSample = realtime.location
        startVerification(reason: "恢复已持久化目标")
    }

    func retry(reason: String = "用户重新检测") {
        guard target != nil else { return }
        startVerification(reason: reason)
    }

    func clear() {
        generation &+= 1
        verificationTask?.cancel()
        verificationTask = nil
        target = nil
        previousSample = nil
        status = .idle
        RuntimeLogger.info("APP", "定位生效检测", "已清除生效检测状态")
    }

    private func startVerification(reason: String) {
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
                "请求精度": "100m"
            ])

            var lastStatus: LocationEffectStatus = .unavailable
            var receivedSample = false

            for attempt in 1...3 {
                guard !Task.isCancelled, currentGeneration == self.generation else { return }
                self.status = .refreshing(attempt: attempt)

                if attempt == 1 {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                }
                guard !Task.isCancelled, currentGeneration == self.generation else { return }

                guard let sample = await self.realtime.requestFreshLocation(
                    desiredAccuracy: kCLLocationAccuracyHundredMeters
                ) else {
                    RuntimeLogger.warning("APP", "定位生效检测", "本轮软刷新未获取到新样本", details: [
                        "attempt": String(attempt)
                    ])
                    continue
                }

                receivedSample = true
                lastStatus = LocationEffectEvaluator.evaluate(
                    target: target,
                    sample: sample,
                    previousSample: self.previousSample
                )
                self.status = lastStatus

                let targetLocation = CLLocation(latitude: target.latitude, longitude: target.longitude)
                RuntimeLogger.info("APP", "定位生效检测", "收到软刷新样本", details: [
                    "attempt": String(attempt),
                    "判定": lastStatus.diagnosticName,
                    "距目标米": String(format: "%.1f", sample.distance(from: targetLocation)),
                    "horizontalAccuracy": String(format: "%.1f", sample.horizontalAccuracy),
                    "样本时间": ISO8601DateFormatter().string(from: sample.timestamp)
                ])

                switch lastStatus {
                case .effective, .gpsLikelyDominant:
                    return
                case .idle, .refreshing, .cachePending, .unavailable:
                    break
                }
            }

            guard !Task.isCancelled, currentGeneration == self.generation else { return }
            self.status = receivedSample ? lastStatus : .unavailable
        }
    }
}
