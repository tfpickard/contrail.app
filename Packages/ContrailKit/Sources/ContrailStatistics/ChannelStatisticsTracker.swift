import Foundation

/// §8's window selection: 1/5/30 minutes, or whole-flight.
public enum StatisticsWindow: String, Sendable, CaseIterable, Equatable {
    case oneMinute, fiveMinutes, thirtyMinutes, wholeFlight

    var duration: TimeInterval? {
        switch self {
        case .oneMinute: return 60
        case .fiveMinutes: return 5 * 60
        case .thirtyMinutes: return 30 * 60
        case .wholeFlight: return nil
        }
    }
}

/// One channel's full set of windowed statistics — the four `WindowedChannelTracker`
/// instances §2.4 calls for, fed from a single incoming sample stream. This is what
/// "adding a window later is a configuration change, not new code" (§2.4) looks like
/// concretely: a fifth window is one more `StatisticsWindow` case and one more
/// tracker instance, not new aggregation logic.
public final class ChannelStatisticsTracker {
    private var trackers: [StatisticsWindow: WindowedChannelTracker]

    public init(expectedRange: ClosedRange<Double>, binCount: Int = 200) {
        var trackers: [StatisticsWindow: WindowedChannelTracker] = [:]
        for window in StatisticsWindow.allCases {
            trackers[window] = WindowedChannelTracker(
                windowDuration: window.duration, expectedRange: expectedRange, binCount: binCount
            )
        }
        self.trackers = trackers
    }

    public func insert(_ sample: TimestampedValue) {
        for tracker in trackers.values {
            tracker.insert(sample)
        }
    }

    public func statistics(for window: StatisticsWindow) -> ChannelWindowStatistics {
        trackers[window]!.statistics
    }
}
