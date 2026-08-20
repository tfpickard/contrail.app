import Foundation
import Testing
@testable import ContrailTurbulence

struct SlidingRMSTests {
    private let base = Date(timeIntervalSince1970: 1_755_639_600)

    @Test func matchesDirectComputationWithNoEviction() {
        var rms = SlidingRMS(windowDuration: 100)
        let values = [3.0, 4.0, 0.0, -5.0]
        var lastResult = 0.0
        for (i, v) in values.enumerated() {
            lastResult = rms.insert(base.addingTimeInterval(Double(i)), v)
        }
        let expected = (values.map { $0 * $0 }.reduce(0, +) / Double(values.count)).squareRoot()
        #expect(abs(lastResult - expected) < 1e-9)
    }

    @Test func evictsSamplesOlderThanTheWindow() {
        var rms = SlidingRMS(windowDuration: 5)
        _ = rms.insert(base, 100) // will be evicted
        for i in 1...10 {
            _ = rms.insert(base.addingTimeInterval(Double(i)), 1)
        }
        // Only the trailing ~5 seconds of 1.0-valued samples remain -- RMS should
        // be close to 1.0, not inflated by the long-evicted 100.
        #expect(abs(rms.insert(base.addingTimeInterval(10), 1) - 1.0) < 0.01)
    }

    @Test func emptyWindowReturnsZero() {
        var rms = SlidingRMS(windowDuration: 10)
        let result = rms.insert(base, 0)
        #expect(result == 0)
    }

    @Test func allZerosGivesZeroRMS() {
        var rms = SlidingRMS(windowDuration: 10)
        var last = -1.0
        for i in 0..<5 {
            last = rms.insert(base.addingTimeInterval(Double(i)), 0)
        }
        #expect(last == 0)
    }
}
