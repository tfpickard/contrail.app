import Foundation

/// Rolling percentiles (p50/p95/p99) at O(1) insert *and* evict — a genuine sliding-
/// window quantile needs an order-statistic structure at O(log n) per sample; a
/// fixed-bin histogram trades exactness for O(1) by rounding to bin width, which is
/// the right trade here (the spec's own bar is "exact to bin width," not exact to
/// the sample — see the plan's pushback notes). Bin bounds are the channel's known
/// physical range; a value outside it clamps to the nearest edge bin.
///
/// Mean/standard deviation are tracked via running sums (`Σx`, `Σx²`), also updated
/// on both insert and remove — exact in principle, but floating-point subtraction on
/// `remove` means these can drift over a multi-hour flight's millions of updates.
/// Not resynced periodically in this pass; a known, documented limitation rather
/// than a silently swept-under-the-rug one.
struct BinnedHistogram {
    private var counts: [Int]
    private let lowerBound: Double
    private let upperBound: Double
    private let binWidth: Double

    private(set) var totalCount = 0
    private var sum: Double = 0
    private var sumOfSquares: Double = 0

    init(range: ClosedRange<Double>, binCount: Int = 200) {
        precondition(binCount > 0)
        precondition(range.upperBound > range.lowerBound)
        lowerBound = range.lowerBound
        upperBound = range.upperBound
        binWidth = (range.upperBound - range.lowerBound) / Double(binCount)
        counts = Array(repeating: 0, count: binCount)
    }

    mutating func insert(_ value: Double) {
        counts[binIndex(for: value)] += 1
        totalCount += 1
        sum += value
        sumOfSquares += value * value
    }

    mutating func remove(_ value: Double) {
        let index = binIndex(for: value)
        if counts[index] > 0 { counts[index] -= 1 }
        totalCount = Swift.max(0, totalCount - 1)
        sum -= value
        sumOfSquares -= value * value
    }

    var mean: Double? {
        totalCount > 0 ? sum / Double(totalCount) : nil
    }

    var standardDeviation: Double? {
        guard totalCount > 0 else { return nil }
        let m = sum / Double(totalCount)
        let variance = Swift.max(0, sumOfSquares / Double(totalCount) - m * m)
        return variance.squareRoot()
    }

    /// `p` in `[0, 1]`. Returns the midpoint of the bin containing the requested
    /// rank — "exact to bin width," per this type's documented trade-off.
    func percentile(_ p: Double) -> Double? {
        guard totalCount > 0 else { return nil }
        let targetRank = p * Double(totalCount - 1)
        var cumulative = 0
        for (index, binCount) in counts.enumerated() {
            cumulative += binCount
            if Double(cumulative - 1) >= targetRank {
                return lowerBound + (Double(index) + 0.5) * binWidth
            }
        }
        return upperBound
    }

    private func binIndex(for value: Double) -> Int {
        let clamped = Swift.min(Swift.max(value, lowerBound), upperBound)
        let index = Int((clamped - lowerBound) / binWidth)
        return Swift.min(Swift.max(index, 0), counts.count - 1)
    }
}
