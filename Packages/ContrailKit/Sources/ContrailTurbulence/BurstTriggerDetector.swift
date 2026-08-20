import Foundation

/// §3: "event-triggered burst: when filtered vertical acceleration variance exceeds
/// an adaptive threshold, log at full rate for a hold-off period, then decay back...
/// the threshold is a multiple of a rolling baseline of vertical acceleration
/// variance, not a fixed constant, so it self-calibrates to the airframe and to
/// where the passenger is sitting relative to the wing."
///
/// Two timescales, both via `SlidingRMS`: a short window (fast-reacting — "is
/// something happening right now") and a long window (the rolling baseline —
/// "what's normal on this flight, in this seat"). `rms²` stands in for variance
/// throughout — valid because the primary band-pass filter's output is already
/// ~zero-mean by construction (that's what a high-pass does), so mean-square and
/// variance coincide here.
public struct BurstTriggerDetector: Sendable {
    private var shortWindow: SlidingRMS
    private var longWindow: SlidingRMS
    private let thresholdMultiplier: Double
    private let holdOffDuration: TimeInterval
    private var lastAboveThresholdTime: Date?

    public init(
        thresholdMultiplier: Double = 4.0,
        holdOffDuration: TimeInterval = 30,
        shortWindowDuration: TimeInterval = 2,
        longWindowDuration: TimeInterval = 60
    ) {
        shortWindow = SlidingRMS(windowDuration: shortWindowDuration)
        longWindow = SlidingRMS(windowDuration: longWindowDuration)
        self.thresholdMultiplier = thresholdMultiplier
        self.holdOffDuration = holdOffDuration
    }

    /// Feeds one filtered vertical-acceleration sample and returns whether a burst
    /// is *currently* active — either just triggered, or still within the hold-off
    /// decay period of a recent trigger. The "decay back" §3 asks for falls out
    /// naturally from the hold-off: once nothing exceeds the threshold for
    /// `holdOffDuration`, this returns to `false` on its own.
    public mutating func ingest(timestamp: Date, filteredValue: Double) -> Bool {
        let shortRMS = shortWindow.insert(timestamp, filteredValue)
        let longRMS = longWindow.insert(timestamp, filteredValue)

        let shortVariance = shortRMS * shortRMS
        let longVariance = longRMS * longRMS

        // Needs a real baseline before it can self-calibrate -- without this guard,
        // an empty/near-empty long window would make the threshold trivially small
        // and everything would "trigger" at flight start.
        if longWindow.sampleCount > 10, shortVariance > thresholdMultiplier * Swift.max(longVariance, 1e-9) {
            lastAboveThresholdTime = timestamp
        }

        guard let last = lastAboveThresholdTime else { return false }
        return timestamp.timeIntervalSince(last) <= holdOffDuration
    }
}
