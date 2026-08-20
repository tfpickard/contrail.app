import Foundation
import Testing
@testable import ContrailStatistics

struct MonotonicMinMaxTrackerTests {
    private let base = Date(timeIntervalSince1970: 1_755_639_600)

    @Test func tracksMinAndMaxWithNoEviction() {
        var tracker = MonotonicMinMaxTracker()
        let values = [5.0, 3.0, 8.0, 1.0, 9.0, 2.0]
        for (i, v) in values.enumerated() {
            tracker.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: v))
        }
        #expect(tracker.min == 1.0)
        #expect(tracker.max == 9.0)
    }

    @Test func evictionRemovesExpiredExtremaAndRevealsTheNextOne() {
        var tracker = MonotonicMinMaxTracker()
        // The max (100) arrives first, then falls out of the window.
        tracker.insert(TimestampedValue(timestamp: base, value: 100))
        tracker.insert(TimestampedValue(timestamp: base.addingTimeInterval(10), value: 5))
        tracker.insert(TimestampedValue(timestamp: base.addingTimeInterval(20), value: 7))

        tracker.evict(olderThan: base.addingTimeInterval(5)) // evicts only the 100 (t=0 < t=5)
        #expect(tracker.max == 7)
        #expect(tracker.min == 5)
    }

    @Test func emptyTrackerReturnsNil() {
        let tracker = MonotonicMinMaxTracker()
        #expect(tracker.min == nil)
        #expect(tracker.max == nil)
    }

    /// Verified against a brute-force O(n) rescan over the actual in-window
    /// samples, at every step of a randomized-shaped (but deterministic —
    /// sinusoidal, not `Double.random`) insert/evict sequence, over a sliding
    /// window. This is the correctness property that actually matters: the
    /// monotonic deque must agree with the naive definition at every point, not
    /// just in a couple of hand-picked cases.
    @Test func agreesWithBruteForceOverASlidingWindow() {
        var tracker = MonotonicMinMaxTracker()
        var windowContents: [TimestampedValue] = []
        let windowDuration: TimeInterval = 30

        for i in 0..<500 {
            let t = base.addingTimeInterval(Double(i) * 0.7)
            let value = sin(Double(i) * 0.31) * 50 + cos(Double(i) * 0.053) * 20
            let sample = TimestampedValue(timestamp: t, value: value)

            tracker.insert(sample)
            windowContents.append(sample)

            let cutoff = t.addingTimeInterval(-windowDuration)
            tracker.evict(olderThan: cutoff)
            windowContents.removeAll { $0.timestamp < cutoff }

            let expectedMin = windowContents.map(\.value).min()
            let expectedMax = windowContents.map(\.value).max()
            #expect(tracker.min == expectedMin, "min mismatch at step \(i)")
            #expect(tracker.max == expectedMax, "max mismatch at step \(i)")
        }
    }
}
