import Foundation
import Testing
@testable import ContrailAnalytics

struct SampleDistributionTests {
    @Test func emptyInputReturnsNil() {
        #expect(SampleDistribution.compute([]) == nil)
    }

    @Test func computesMeanMinMaxAndStandardDeviation() throws {
        let distribution = try #require(SampleDistribution.compute([1, 2, 3, 4, 5]))
        #expect(distribution.count == 5)
        #expect(distribution.mean == 3)
        #expect(distribution.min == 1)
        #expect(distribution.max == 5)
        #expect(abs(distribution.standardDeviation - 1.4142135623) < 0.0001)
    }

    @Test func percentilesAreMonotonicallyNondecreasing() throws {
        let values = (1...100).map { Double($0) }
        let distribution = try #require(SampleDistribution.compute(values))
        #expect(distribution.p50 <= distribution.p95)
        #expect(distribution.p95 <= distribution.p99)
        #expect(distribution.p99 <= distribution.max)
    }

    @Test func singleValuePopulationHasZeroSpread() throws {
        let distribution = try #require(SampleDistribution.compute([7, 7, 7]))
        #expect(distribution.mean == 7)
        #expect(distribution.min == 7)
        #expect(distribution.max == 7)
        #expect(distribution.standardDeviation == 0)
    }
}
