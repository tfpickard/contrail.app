import Foundation
import ContrailCore

/// §3's adaptive-sampling policy: which `EstimatorOutput`s actually get written to
/// the flight log. The sensor stream itself never slows down (§3: "sensor rate is
/// fixed and high... you cannot detect a bump with a sensor you have turned down"),
/// but the *logging* rate varies — sparse at cruise, high during critical phases,
/// and full-rate the instant a burst triggers, with the pre-trigger leading edge
/// flushed alongside it.
///
/// Deliberately separate from `Estimator` itself: `Estimator`'s job is computing the
/// current true state; this type's job is deciding what's worth persisting. Feed it
/// every `EstimatorOutput` the estimator produces (at full rate — call this from the
/// same loop that calls `Estimator.ingest`, not the throttled UI cadence), and it
/// returns the subset that should actually be written.
public final class AdaptiveLoggingController {
    private var burstDetector: BurstTriggerDetector
    /// Everything from the trailing `preTriggerDuration` that hasn't been written
    /// yet — flushed whole the instant a burst newly triggers, so the "leading edge
    /// of the event" (§3) isn't lost to a naive post-trigger-only capture.
    private var pendingBuffer: [EstimatorOutput] = []
    private let preTriggerDuration: TimeInterval
    private var lastWrittenTime: Date?
    private var wasBursting = false

    public init(
        preTriggerDuration: TimeInterval = 10,
        burstDetector: BurstTriggerDetector = BurstTriggerDetector()
    ) {
        self.preTriggerDuration = preTriggerDuration
        self.burstDetector = burstDetector
    }

    /// - Parameters:
    ///   - output: the latest estimator output.
    ///   - filteredVerticalAcceleration: `Estimator.latestFilteredVerticalAcceleration`
    ///     at this instant — the fast-reacting burst-detection signal, `nil` while
    ///     the attitude gate is closed (§4.1's handling-motion rejection applies
    ///     here too: handling motion must never itself trigger burst-rate logging).
    /// - Returns: the records to write right now — usually zero or one, but more
    ///   than one exactly when a burst has just triggered and pre-trigger history
    ///   flushes alongside it.
    public func decide(output: EstimatorOutput, filteredVerticalAcceleration: Double?) -> [EstimatorOutput] {
        pendingBuffer.append(output)
        let bufferCutoff = output.t.addingTimeInterval(-preTriggerDuration)
        pendingBuffer.removeAll { $0.t < bufferCutoff }

        let isBursting: Bool
        if let filtered = filteredVerticalAcceleration {
            isBursting = burstDetector.ingest(timestamp: output.t, filteredValue: filtered)
        } else {
            isBursting = false
        }
        let justTriggered = isBursting && !wasBursting
        wasBursting = isBursting

        if justTriggered {
            let unwritten = pendingBuffer.filter { sample in
                lastWrittenTime.map { sample.t > $0 } ?? true
            }
            if let newest = unwritten.last?.t { lastWrittenTime = newest }
            return unwritten
        }

        let floorInterval = Self.floorLoggingInterval(phase: output.phase.value, isBursting: isBursting)
        if let last = lastWrittenTime, output.t.timeIntervalSince(last) < floorInterval {
            return []
        }
        lastWrittenTime = output.t
        return [output]
    }

    /// §3: "per-phase floor rates: high during taxi, takeoff, climb, descent, and
    /// landing; low at cruise (30-60 s between records is fine)." 45s is the
    /// midpoint of that stated range. "High" is 1s — a real floor rate, not the raw
    /// 50-100 Hz sensor rate, which would be excessive log volume for a rate that's
    /// meant to be a *floor*, not the burst rate.
    private static func floorLoggingInterval(phase: FlightPhase?, isBursting: Bool) -> TimeInterval {
        if isBursting { return 0 } // full rate: write every call while a burst is active
        switch phase {
        case .taxi, .takeoff, .climb, .descent, .landing: return 1.0
        case .cruise, .none: return 45.0
        }
    }
}
