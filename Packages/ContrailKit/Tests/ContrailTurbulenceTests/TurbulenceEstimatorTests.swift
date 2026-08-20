import Foundation
import Testing
import ContrailSensors
@testable import ContrailTurbulence

struct TurbulenceEstimatorTests {
    private let base = Date(timeIntervalSince1970: 1_755_639_600)
    private let sampleRate = 50.0
    private let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

    private func sample(at i: Int, verticalAccel: Double, attitude: Quaternion) -> MotionSample {
        MotionSample(
            timestamp: base.addingTimeInterval(Double(i) / sampleRate),
            userAcceleration: Vector3(x: 0, y: 0, z: verticalAccel),
            gravity: Vector3(x: 0, y: 0, z: -1),
            attitude: attitude,
            rotationRate: Vector3(x: 0, y: 0, z: 0)
        )
    }

    @Test func quietStableFlightReadsLowEDR() {
        let estimator = TurbulenceEstimator(sampleRateHz: sampleRate)
        var lastEDR: Double?
        // Small deterministic (not random) high-frequency dither, well below any
        // real turbulence amplitude -- the kind of noise floor a phone at rest on a
        // tray table would show.
        for i in 0..<1000 {
            let accel = sin(Double(i) * 1.7) * 0.01
            let output = estimator.ingest(sample(at: i, verticalAccel: accel, attitude: identity))
            if let edr = output.edrCubeRoot { lastEDR = edr }
        }
        #expect(lastEDR! < 0.05)
    }

    @Test func realTurbulenceLikeSignalReadsMeaningfullyHigherEDRThanQuiet() {
        func runScenario(amplitude: Double) -> Double {
            let estimator = TurbulenceEstimator(sampleRateHz: sampleRate)
            var lastEDR: Double = 0
            for i in 0..<1000 {
                // A broadband-ish signal: sum of a few incommensurate frequencies
                // inside the primary 0.1-10 Hz band, deterministic rather than
                // Double.random so the test is exactly reproducible.
                let t = Double(i) / sampleRate
                let accel = amplitude * (
                    sin(2 * .pi * 0.5 * t) + 0.6 * sin(2 * .pi * 2.0 * t) + 0.3 * sin(2 * .pi * 4.0 * t)
                )
                let output = estimator.ingest(sample(at: i, verticalAccel: accel, attitude: identity))
                if let edr = output.edrCubeRoot { lastEDR = edr }
            }
            return lastEDR
        }

        let quiet = runScenario(amplitude: 0.01)
        let turbulent = runScenario(amplitude: 2.0)
        #expect(turbulent > quiet * 10)
    }

    @Test func attitudeGateSuppressesEDRDuringHandlingMotion() {
        let estimator = TurbulenceEstimator(sampleRateHz: sampleRate, attitudeGateMaxDegrees: 2)
        var sawGateClose = false
        var edrReportedWhileGateClosed = false

        for i in 0..<200 {
            // A sudden large, sustained attitude change starting partway through --
            // simulating someone picking the phone up -- alongside a real vertical
            // acceleration transient (handling motion often does produce large
            // accelerations too; the gate, not the accelerometer, is what should
            // reject it).
            let handling = i >= 50 && i < 150
            let attitude: Quaternion = handling
                ? Quaternion(x: 0, y: 0, z: sin(.pi / 8), w: cos(.pi / 8)) // ~45 degrees
                : identity
            let accel = handling ? 3.0 : 0.02

            let output = estimator.ingest(sample(at: i, verticalAccel: accel, attitude: attitude))
            if !output.attitudeGateOpen {
                sawGateClose = true
                if output.edrCubeRoot != nil { edrReportedWhileGateClosed = true }
            }
        }

        #expect(sawGateClose)
        #expect(!edrReportedWhileGateClosed)
    }

    @Test func discriminatorRMSIsReportedAlongsideEDRWhenGateIsOpen() {
        let estimator = TurbulenceEstimator(sampleRateHz: sampleRate)
        var sawDiscriminatorValue = false
        for i in 0..<300 {
            let t = Double(i) / sampleRate
            let accel = sin(2 * .pi * 8 * t) // inside the 5-20 Hz discriminator band
            let output = estimator.ingest(sample(at: i, verticalAccel: accel, attitude: identity))
            if let d = output.discriminatorRMS, d > 0 { sawDiscriminatorValue = true }
        }
        #expect(sawDiscriminatorValue)
    }
}
