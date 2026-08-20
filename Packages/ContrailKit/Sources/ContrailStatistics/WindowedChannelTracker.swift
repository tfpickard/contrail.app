import Foundation

/// A snapshot of one channel's statistics over one window, at a point in time.
public struct ChannelWindowStatistics: Sendable, Equatable {
    public let mean: Double?
    public let min: Double?
    public let max: Double?
    public let standardDeviation: Double?
    public let p50: Double?
    public let p95: Double?
    public let p99: Double?
    public let sampleCount: Int
}

/// §2.4's window tracker for one (channel, window) pair. §2.4 requires that "adding
/// a window later must be a configuration change, not new code" — this type *is*
/// that configuration: one channel gets four instances (1 min, 5 min, 30 min,
/// whole-flight), differing only in `windowDuration`, sharing this exact
/// implementation. `windowDuration == nil` means whole-flight — nothing is ever
/// evicted.
public final class WindowedChannelTracker {
    private let windowDuration: TimeInterval?
    private var samples = RingDeque<TimestampedValue>()
    private var minMax = MonotonicMinMaxTracker()
    private var histogram: BinnedHistogram

    public init(windowDuration: TimeInterval?, expectedRange: ClosedRange<Double>, binCount: Int = 200) {
        self.windowDuration = windowDuration
        self.histogram = BinnedHistogram(range: expectedRange, binCount: binCount)
    }

    public func insert(_ sample: TimestampedValue) {
        samples.pushBack(sample)
        minMax.insert(sample)
        histogram.insert(sample.value)

        guard let windowDuration else { return }
        let cutoff = sample.timestamp.addingTimeInterval(-windowDuration)
        minMax.evict(olderThan: cutoff)
        while let oldest = samples.first, oldest.timestamp < cutoff {
            histogram.remove(oldest.value)
            samples.popFront()
        }
    }

    public var statistics: ChannelWindowStatistics {
        ChannelWindowStatistics(
            mean: histogram.mean,
            min: minMax.min,
            max: minMax.max,
            standardDeviation: histogram.standardDeviation,
            p50: histogram.percentile(0.5),
            p95: histogram.percentile(0.95),
            p99: histogram.percentile(0.99),
            sampleCount: histogram.totalCount
        )
    }
}
