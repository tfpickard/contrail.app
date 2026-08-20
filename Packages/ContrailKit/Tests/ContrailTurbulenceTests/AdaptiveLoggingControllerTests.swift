import Foundation
import Testing
import ContrailCore
@testable import ContrailTurbulence

private func makeOutput(t: Date, phase: FlightPhase?) -> EstimatorOutput {
    EstimatorOutput(
        t: t,
        uptime: t.timeIntervalSince1970,
        position: PositionEstimate(
            fused: .unavailable, confidenceRadius: .unavailable, gnss: .unavailable, deadReckoned: .unavailable,
            horizontalAccuracy: .unavailable, verticalAccuracy: .unavailable, timeSinceValidFix: .unavailable,
            altitudeGPS: .unavailable
        ),
        motion: MotionEstimate(
            groundspeed: .unavailable, trueCourse: .unavailable, trackAngleRate: .unavailable,
            verticalSpeed: .unavailable, longitudinalAcceleration: .unavailable, clSpeed: .unavailable, clCourse: .unavailable
        ),
        cabin: CabinEnvironment(pressure: .unavailable, pressureAltitude: .unavailable, pressurizationRate: .unavailable),
        turbulence: .unavailable,
        route: RouteRelative(
            alongTrackFlown: .unavailable, alongTrackRemaining: .unavailable, crossTrackError: .unavailable,
            fractionalProgress: .unavailable, nearestCity: .unavailable, eta: .unavailable
        ),
        phase: phase.map { Channel(value: $0, source: .derived) } ?? .unavailable
    )
}

struct AdaptiveLoggingControllerTests {
    private let base = Date(timeIntervalSince1970: 1_755_639_600)

    @Test func atCruiseWritesNoMoreOftenThanTheFloorInterval() {
        let controller = AdaptiveLoggingController()
        var totalWritten = 0
        // 60 seconds of cruise samples at 10 Hz (600 calls) -- the 45s cruise floor
        // should yield at most 2 writes (one at start, maybe one more near the end).
        for i in 0..<600 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            totalWritten += controller.decide(output: makeOutput(t: t, phase: .cruise), filteredVerticalAcceleration: 0).count
        }
        #expect(totalWritten <= 3)
        #expect(totalWritten >= 1)
    }

    @Test func atTaxiWritesRoughlyOncePerSecond() {
        let controller = AdaptiveLoggingController()
        var totalWritten = 0
        // 10 seconds of taxi samples at 10 Hz (100 calls) -- the 1s floor should
        // yield roughly 10 writes.
        for i in 0..<100 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            totalWritten += controller.decide(output: makeOutput(t: t, phase: .taxi), filteredVerticalAcceleration: 0).count
        }
        #expect(totalWritten >= 8)
        #expect(totalWritten <= 12)
    }

    @Test func firstCallAlwaysWritesImmediately() {
        let controller = AdaptiveLoggingController()
        let result = controller.decide(output: makeOutput(t: base, phase: .cruise), filteredVerticalAcceleration: 0)
        #expect(result.count == 1)
    }

    @Test func burstTriggerFlushesUnwrittenPreTriggerHistory() {
        let controller = AdaptiveLoggingController(preTriggerDuration: 10)
        // Establish a quiet baseline at cruise (sparse writes, but the pre-trigger
        // ring buffer accumulates every sample regardless of write decisions).
        for i in 0..<200 { // 20 seconds at 10 Hz
            let t = base.addingTimeInterval(Double(i) * 0.1)
            _ = controller.decide(output: makeOutput(t: t, phase: .cruise), filteredVerticalAcceleration: 0.01)
        }

        // A sudden burst -- large amplitude, well above the established baseline.
        var flushedOnTrigger: [EstimatorOutput] = []
        for i in 200..<230 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            let written = controller.decide(
                output: makeOutput(t: t, phase: .cruise),
                filteredVerticalAcceleration: 2.0
            )
            if written.count > 1 {
                flushedOnTrigger = written
                break
            }
        }

        // The flush should include samples from *before* the trigger instant --
        // the whole point of pre-trigger capture (section 3: "a naive trigger
        // loses the leading edge of the event").
        #expect(flushedOnTrigger.count > 1)
        if let first = flushedOnTrigger.first, let last = flushedOnTrigger.last {
            #expect(first.t < last.t)
        }
    }

    @Test func burstFullRateLoggingWritesEverySample() {
        let controller = AdaptiveLoggingController()

        // A quiet baseline first -- a genuinely *constant* signal has zero
        // short-vs-long variance contrast and would never trigger on its own, no
        // matter the amplitude; the detector reacts to a *change*, not a level.
        for i in 0..<300 { // 30s at 10 Hz
            let t = base.addingTimeInterval(Double(i) * 0.1)
            _ = controller.decide(
                output: makeOutput(t: t, phase: .cruise),
                filteredVerticalAcceleration: sin(Double(i) * 0.9) * 0.02
            )
        }

        // Then a sustained, oscillating high-amplitude burst -- short enough
        // (10s) to stay well within the 60s long-window's slower adaptation, so
        // short-vs-long contrast (and thus triggering) persists throughout.
        var writesDuringSustainedBurst = 0
        for i in 300..<400 {
            let t = base.addingTimeInterval(Double(i) * 0.1)
            let written = controller.decide(
                output: makeOutput(t: t, phase: .cruise),
                filteredVerticalAcceleration: sin(Double(i) * 0.9) * 3.0
            )
            writesDuringSustainedBurst += written.count
        }
        // Once truly in a sustained burst (full rate = every call), this should be
        // close to the call count, not throttled down to the ~2 cruise-floor writes
        // a quiet period would produce.
        #expect(writesDuringSustainedBurst > 50)
    }
}
