import Testing
@testable import ContrailStatistics

struct BinnedHistogramTests {
    @Test func meanAndStandardDeviationMatchDirectComputation() {
        var histogram = BinnedHistogram(range: 0...100, binCount: 1000)
        let values = [10.0, 20.0, 30.0, 40.0, 50.0]
        for v in values { histogram.insert(v) }

        let expectedMean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - expectedMean) * ($1 - expectedMean) } / Double(values.count)
        let expectedStdDev = variance.squareRoot()

        #expect(abs(histogram.mean! - expectedMean) < 0.001)
        #expect(abs(histogram.standardDeviation! - expectedStdDev) < 0.001)
    }

    @Test func medianOfSymmetricDataIsApproximatelyCorrect() {
        var histogram = BinnedHistogram(range: 0...100, binCount: 1000)
        for v in stride(from: 0.0, through: 100.0, by: 1.0) { histogram.insert(v) }
        #expect(abs(histogram.percentile(0.5)! - 50) < 1)
    }

    @Test func removeUndoesAnInsertExactly() {
        var withExtra = BinnedHistogram(range: 0...100, binCount: 500)
        for v in [10.0, 20.0, 30.0] { withExtra.insert(v) }
        withExtra.insert(99.0)
        withExtra.remove(99.0)

        var withoutExtra = BinnedHistogram(range: 0...100, binCount: 500)
        for v in [10.0, 20.0, 30.0] { withoutExtra.insert(v) }

        #expect(withExtra.totalCount == withoutExtra.totalCount)
        #expect(abs(withExtra.mean! - withoutExtra.mean!) < 1e-9)
    }

    @Test func valuesOutsideRangeClampToNearestEdgeBin() {
        var histogram = BinnedHistogram(range: 0...10, binCount: 10)
        histogram.insert(-500)
        histogram.insert(500)
        // Both land in edge bins -- percentile queries should still return finite,
        // in-range values, not crash or return nonsense.
        #expect(histogram.percentile(0.0)! >= 0)
        #expect(histogram.percentile(1.0)! <= 10)
    }

    @Test func emptyHistogramReturnsNilForEverything() {
        let histogram = BinnedHistogram(range: 0...100)
        #expect(histogram.mean == nil)
        #expect(histogram.standardDeviation == nil)
        #expect(histogram.percentile(0.5) == nil)
    }

    @Test func percentilesAreMonotonicallyNondecreasing() {
        var histogram = BinnedHistogram(range: 0...1000, binCount: 500)
        for v in stride(from: 0.0, through: 1000.0, by: 3.7) { histogram.insert(v) }
        let p50 = histogram.percentile(0.5)!
        let p95 = histogram.percentile(0.95)!
        let p99 = histogram.percentile(0.99)!
        #expect(p50 <= p95)
        #expect(p95 <= p99)
    }
}
