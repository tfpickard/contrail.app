import Foundation

/// §2.4: "rolling min/max must use a monotonic deque for amortized O(1) per sample —
/// a naive O(n) rescan over a 30-minute window at high sample rate will destroy the
/// battery." Two deques, one per direction: the min deque holds candidates in
/// non-decreasing value order (front is always the current min), the max deque in
/// non-increasing order (front is always the current max). On insert, anything at
/// the back that could never become the extremum again — because the new sample is
/// more extreme and arrived later — is popped first; this is what keeps each deque
/// monotonic and bounds its size by the number of "records" seen, not the window
/// length.
struct MonotonicMinMaxTracker {
    private var minDeque = RingDeque<TimestampedValue>()
    private var maxDeque = RingDeque<TimestampedValue>()

    mutating func insert(_ sample: TimestampedValue) {
        while let last = minDeque.last, last.value >= sample.value { minDeque.popBack() }
        minDeque.pushBack(sample)

        while let last = maxDeque.last, last.value <= sample.value { maxDeque.popBack() }
        maxDeque.pushBack(sample)
    }

    /// Evicts entries older than `cutoff`. Must be called with the *same* cutoff
    /// used to evict the raw sample buffer, or min/max will disagree with the
    /// window's other statistics about which samples are still "in".
    mutating func evict(olderThan cutoff: Date) {
        while let first = minDeque.first, first.timestamp < cutoff { minDeque.popFront() }
        while let first = maxDeque.first, first.timestamp < cutoff { maxDeque.popFront() }
    }

    var min: Double? { minDeque.first?.value }
    var max: Double? { maxDeque.first?.value }
}
