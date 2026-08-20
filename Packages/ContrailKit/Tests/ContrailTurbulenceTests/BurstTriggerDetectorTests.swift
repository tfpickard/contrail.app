import Foundation
import Testing
@testable import ContrailTurbulence

struct BurstTriggerDetectorTests {
    private let base = Date(timeIntervalSince1970: 1_755_639_600)

    /// Feeds a quiet baseline (to establish a rolling variance floor), then a
    /// sudden large-amplitude burst, and confirms the detector reacts.
    @Test func triggersOnASuddenLargeAmplitudeIncrease() {
        var detector = BurstTriggerDetector(
            thresholdMultiplier: 4, holdOffDuration: 10, shortWindowDuration: 1, longWindowDuration: 30
        )
        var lastTriggered = false

        // Quiet baseline for 60 seconds at 10 Hz.
        for i in 0..<600 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            let value = sin(Double(i) * 0.9) * 0.02
            lastTriggered = detector.ingest(timestamp: t, filteredValue: value)
        }
        #expect(!lastTriggered, "should not trigger on the quiet baseline itself")

        // A sudden burst, 20x the baseline amplitude.
        var triggeredDuringBurst = false
        for i in 600..<650 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            let value = sin(Double(i) * 0.9) * 0.4
            if detector.ingest(timestamp: t, filteredValue: value) {
                triggeredDuringBurst = true
            }
        }
        #expect(triggeredDuringBurst)
    }

    @Test func decaysBackToFalseAfterTheHoldOffPeriod() {
        var detector = BurstTriggerDetector(
            thresholdMultiplier: 4, holdOffDuration: 5, shortWindowDuration: 1, longWindowDuration: 30
        )
        for i in 0..<300 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            _ = detector.ingest(timestamp: t, filteredValue: sin(Double(i) * 0.9) * 0.02)
        }
        // Brief burst.
        for i in 300..<310 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            _ = detector.ingest(timestamp: t, filteredValue: sin(Double(i) * 0.9) * 0.4)
        }
        // Quiet again, well past the 5-second hold-off.
        var stillTriggered = true
        for i in 310..<400 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            stillTriggered = detector.ingest(timestamp: t, filteredValue: sin(Double(i) * 0.9) * 0.02)
        }
        #expect(!stillTriggered)
    }

    @Test func doesNotTriggerOnAFlatConstantSignal() {
        var detector = BurstTriggerDetector(shortWindowDuration: 1, longWindowDuration: 30)
        var anyTriggered = false
        for i in 0..<500 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            if detector.ingest(timestamp: t, filteredValue: 0) { anyTriggered = true }
        }
        #expect(!anyTriggered)
    }
}
