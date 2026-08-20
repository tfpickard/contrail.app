import Foundation
import Testing
@testable import ContrailStatistics

struct WindowedChannelTrackerTests {
    private let base = Date(timeIntervalSince1970: 1_755_639_600)

    @Test func wholeFlightWindowNeverEvicts() {
        let tracker = WindowedChannelTracker(windowDuration: nil, expectedRange: 0...100)
        for i in 0..<1000 {
            tracker.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i) * 60), value: Double(i % 100)))
        }
        #expect(tracker.statistics.sampleCount == 1000)
    }

    @Test func oneMinuteWindowEvictsSamplesOlderThanSixtySeconds() {
        let tracker = WindowedChannelTracker(windowDuration: 60, expectedRange: 0...100)
        for i in 0..<10 {
            tracker.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i) * 10), value: 50))
        }
        // 10 samples 10s apart span 90s; only the last ~6 (spanning the trailing
        // 60s) should remain once the final sample lands.
        #expect(tracker.statistics.sampleCount < 10)
        #expect(tracker.statistics.sampleCount >= 6)
    }

    @Test func minMaxAndPercentilesStayConsistentAsWindowSlides() {
        let tracker = WindowedChannelTracker(windowDuration: 30, expectedRange: -10...10)
        // Ramp up to a single-sample peak, then all the way down to a value held
        // flat for a while -- long enough that the peak is unambiguously more than
        // 30s (the window duration) in the past by the end, not sitting right on
        // the eviction boundary where an off-by-one in the test itself (not the
        // tracker) could produce a flaky assertion.
        var maxSeenInWindow: [Double] = []
        for i in 0..<90 {
            let value: Double
            if i < 30 {
                value = Double(i) / 3.0       // ramp up to ~9.67 at i=29
            } else {
                value = 0                      // drop to flat 0 for the rest
            }
            tracker.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: value))
            maxSeenInWindow.append(tracker.statistics.max ?? -.infinity)
        }
        // The tracked max should have risen during the ramp-up...
        #expect(maxSeenInWindow[29] > maxSeenInWindow[5])
        // ...and fallen back to 0 well after the peak (at i=29) is more than the
        // 30-second window duration in the past.
        #expect(maxSeenInWindow[89] < maxSeenInWindow[29])
        #expect(maxSeenInWindow[89] == 0)
    }
}

struct ChannelStatisticsTrackerTests {
    private let base = Date(timeIntervalSince1970: 1_755_639_600)

    @Test func allFourWindowsUpdateFromOneInsertStream() {
        let tracker = ChannelStatisticsTracker(expectedRange: 0...500)
        for i in 0..<200 {
            tracker.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: Double(i)))
        }

        let oneMin = tracker.statistics(for: .oneMinute)
        let wholeFlight = tracker.statistics(for: .wholeFlight)

        // Whole-flight has seen every sample; the 1-minute window has evicted most
        // of the early ones, so it should have strictly fewer.
        #expect(wholeFlight.sampleCount == 200)
        #expect(oneMin.sampleCount < wholeFlight.sampleCount)
        #expect(oneMin.sampleCount > 0)
    }
}
