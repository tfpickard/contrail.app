import Foundation
import Testing
@testable import ContrailStatistics

struct PeakDetectorTests {
    private let base = Date(timeIntervalSince1970: 1_755_639_600)

    @Test func detectsAClearIsolatedBumpAboveTheProminenceThreshold() {
        let detector = PeakDetector(lookback: 3, prominenceThreshold: 5)
        // Flat baseline at 0, with one clear bump to 20 at t=20, well clear of both
        // ends so the detector has full lookback context on both sides.
        for i in 0..<60 {
            let value: Double = i == 20 ? 20 : 0
            detector.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: value))
        }

        #expect(detector.detectedPeaks.count == 1)
        let peak = detector.detectedPeaks[0]
        #expect(peak.value == 20)
        #expect(abs(peak.prominence - 20) < 0.001)
        #expect(peak.timestamp == base.addingTimeInterval(20))
    }

    @Test func doesNotReportBumpsBelowTheProminenceThreshold() {
        let detector = PeakDetector(lookback: 3, prominenceThreshold: 10)
        for i in 0..<60 {
            // A small 3-unit wobble, below the 10-unit threshold.
            let value: Double = i == 20 ? 3 : 0
            detector.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: value))
        }
        #expect(detector.detectedPeaks.isEmpty)
    }

    @Test func attachesThePositionAtTheTimeOfThePeak() {
        let detector = PeakDetector(lookback: 3, prominenceThreshold: 5)
        for i in 0..<60 {
            let value: Double = i == 20 ? 20 : 0
            let position = Coordinate(latitude: Double(i), longitude: -Double(i))
            detector.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: value), position: position)
        }
        #expect(detector.detectedPeaks.first?.position == Coordinate(latitude: 20, longitude: -20))
    }

    @Test func doesNotReportTheSameBumpTwiceAsTheWindowSlides() {
        let detector = PeakDetector(lookback: 3, prominenceThreshold: 5)
        for i in 0..<80 {
            let value: Double = i == 20 ? 20 : 0
            detector.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: value))
        }
        // Even though the window keeps sliding past the same bump for several
        // subsequent inserts, it must only be reported once.
        #expect(detector.detectedPeaks.count == 1)
    }

    @Test func detectsMultipleDistinctBumpsSeparately() {
        let detector = PeakDetector(lookback: 2, prominenceThreshold: 5)
        var values = [Double](repeating: 0, count: 60)
        values[10] = 15
        values[30] = 25
        values[50] = 12
        for (i, v) in values.enumerated() {
            detector.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: v))
        }
        #expect(detector.detectedPeaks.count == 3)
        #expect(detector.detectedPeaks.map(\.value).sorted() == [12, 15, 25])
    }

    @Test func flatSignalProducesNoPeaks() {
        let detector = PeakDetector(lookback: 3, prominenceThreshold: 1)
        for i in 0..<60 {
            detector.insert(TimestampedValue(timestamp: base.addingTimeInterval(Double(i)), value: 42))
        }
        #expect(detector.detectedPeaks.isEmpty)
    }
}
