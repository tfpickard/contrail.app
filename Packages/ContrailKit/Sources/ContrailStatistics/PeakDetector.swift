import Foundation

/// One confirmed local extremum — §2.4: "the three biggest bumps of this flight,"
/// discrete, timestamped, and (via `position`) locatable on the track.
public struct PeakEvent: Sendable, Equatable {
    public let timestamp: Date
    public let value: Double
    public let prominence: Double
    public let position: Coordinate?
}

/// A `Coordinate`-shaped value without depending on `ContrailCore`/`ContrailGeo` —
/// this module stays dependency-free the way `ContrailCore` itself does; the App
/// layer converts to/from `ContrailCore.Coordinate` at the boundary.
public struct Coordinate: Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// §2.4: "local extrema are a separate feature from rolling max... a different data
/// structure and a different user-facing feature than a windowed maximum."
///
/// This is a **causal, streaming approximation** of the offline topological
/// definition of prominence (the one e.g. `scipy.signal.find_peaks` computes): a
/// candidate is confirmed once `lookback` seconds of *future* data exist to compare
/// against, using a bounded `2 × lookback` window rather than scanning the whole
/// flight for the true nearest higher neighbor on each side. Consequences, both
/// deliberate trade-offs for a bounded-memory, real-time detector:
/// - Every peak is reported with a `lookback`-second delay.
/// - A peak's *true* whole-flight prominence could in principle be understated if a
///   still-higher point lies just outside the window.
///
/// The window itself is small (seconds, seeded by `lookback`) — unlike §2.4's
/// rolling min/max, which explicitly warns against an O(n) rescan over a *30-minute*
/// window, an O(n) scan over this much smaller bounded window on every insert is
/// genuinely fine and far simpler than maintaining it incrementally.
public final class PeakDetector {
    private let lookback: TimeInterval
    private let prominenceThreshold: Double
    private var buffer = RingDeque<(sample: TimestampedValue, position: Coordinate?)>()
    private var lastDetectedPeakTime: Date?

    public private(set) var detectedPeaks: [PeakEvent] = []

    public init(lookback: TimeInterval, prominenceThreshold: Double) {
        self.lookback = lookback
        self.prominenceThreshold = prominenceThreshold
    }

    public func insert(_ sample: TimestampedValue, position: Coordinate? = nil) {
        buffer.pushBack((sample, position))

        let bufferCutoff = sample.timestamp.addingTimeInterval(-2 * lookback)
        while let first = buffer.first, first.sample.timestamp < bufferCutoff {
            buffer.popFront()
        }

        evaluateCandidate(now: sample.timestamp)
    }

    private func evaluateCandidate(now: Date) {
        guard let oldest = buffer.first,
              now.timeIntervalSince(oldest.sample.timestamp) >= 2 * lookback else {
            return // not enough history yet to judge a full window
        }

        var maxIndex = 0
        var maxValue = buffer[0].sample.value
        for i in 1..<buffer.elementCount where buffer[i].sample.value > maxValue {
            maxIndex = i
            maxValue = buffer[i].sample.value
        }

        let candidate = buffer[maxIndex]
        // Confirmed only once it has enough trailing data behind it — otherwise
        // it might just be "still rising" and not yet a true local max.
        guard now.timeIntervalSince(candidate.sample.timestamp) >= lookback,
              candidate.sample.timestamp.timeIntervalSince(oldest.sample.timestamp) >= lookback else {
            return
        }

        var beforeMin = Double.infinity
        for i in 0..<maxIndex { beforeMin = Swift.min(beforeMin, buffer[i].sample.value) }
        var afterMin = Double.infinity
        for i in (maxIndex + 1)..<buffer.elementCount { afterMin = Swift.min(afterMin, buffer[i].sample.value) }

        let boundingMin = Swift.min(beforeMin, afterMin)
        guard boundingMin.isFinite else { return } // candidate is at a buffer edge; can't judge yet
        let prominence = candidate.sample.value - boundingMin
        guard prominence >= prominenceThreshold else { return }

        // Don't re-report the same bump as the window slides past it.
        if let last = lastDetectedPeakTime, candidate.sample.timestamp.timeIntervalSince(last) < lookback {
            return
        }

        lastDetectedPeakTime = candidate.sample.timestamp
        detectedPeaks.append(PeakEvent(
            timestamp: candidate.sample.timestamp,
            value: candidate.sample.value,
            prominence: prominence,
            position: candidate.position
        ))
    }
}
