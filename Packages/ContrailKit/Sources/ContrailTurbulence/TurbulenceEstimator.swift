import Foundation
import ContrailSensors

/// One estimator update. `edrCubeRoot`/`discriminatorRMS` are `nil` exactly when
/// `attitudeGateOpen == false` — §4.1: "discard that window entirely" for handling
/// motion, not report a suppressed or zeroed value.
public struct TurbulenceSample: Sendable, Equatable {
    public let timestamp: Date
    /// m^(2/3)/s, the conventional EDR unit — but see `TurbulenceEstimator`'s own
    /// doc comment on what "calibrated" actually means here.
    public let edrCubeRoot: Double?
    public let attitudeGateOpen: Bool
    /// RMS of the 5–20 Hz band — a corroborating discriminator, not the primary
    /// measurement. Real turbulence tends to show broadband energy extending into
    /// this band; handling motion concentrated below ~3 Hz mostly doesn't.
    public let discriminatorRMS: Double?
    /// The instantaneous (not RMS-smoothed) primary-band filtered vertical
    /// acceleration at this sample. Not a display quantity — §3's adaptive-logging
    /// burst detector needs a fast-reacting signal, and `edrCubeRoot`'s 2-second RMS
    /// window would react far too slowly to catch "the leading edge of the event,
    /// which is the most interesting part."
    public let filteredVerticalAcceleration: Double?
}

/// §4.1's measured-turbulence estimator: band-pass filter → attitude gate → RMS →
/// EDR^(1/3). Consumes raw `MotionSample`s (device-frame, from either
/// `ReplaySensorSource` or the live sensor path) one at a time.
///
/// **On calibration — read this before trusting the absolute numbers.** §4.1 itself
/// is explicit that the transfer function between "accelerometer in a phone on a
/// tray table" and "actual airframe response" is unknown and uncalibratable from the
/// device alone. `calibrationScale` is a single linear knob, not a derived physical
/// constant — there is no rigorous airframe-response-factor calculation here (the
/// kind real aviation EDR algorithms use, calibrated per aircraft type against true
/// airspeed and gust alleviation factors). What *is* trustworthy: the DSP chain
/// itself (verified against real frequency-response measurements, not just unit
/// smoke tests) and the relative shape of the output — bigger bumps read bigger.
/// What is not: the absolute EDR value matching a real airline's dispatch report.
/// This is precisely the "calibrated-relative intensity trace, with the
/// absolute-scale caveat stated in the interface, not buried" §4.1 asks for — the
/// caveat belongs in the UI layer that displays this, not just in this comment.
public final class TurbulenceEstimator {
    private var primaryFilter: CascadedBandPassFilter
    private var discriminatorFilter: CascadedBandPassFilter
    private var attitudeGate: AttitudeGate
    private var primaryRMS: SlidingRMS
    private var discriminatorRMS: SlidingRMS
    private let calibrationScale: Double

    public init(
        sampleRateHz: Double,
        rmsWindowDuration: TimeInterval = 2.0,
        attitudeGateMaxDegrees: Double = 2.0,
        calibrationScale: Double = 1.0
    ) {
        primaryFilter = CascadedBandPassFilter(lowCutoffHz: 0.1, highCutoffHz: 10, sampleRateHz: sampleRateHz)
        discriminatorFilter = CascadedBandPassFilter(lowCutoffHz: 5, highCutoffHz: 20, sampleRateHz: sampleRateHz)
        attitudeGate = AttitudeGate(maxAngularChangeDegrees: attitudeGateMaxDegrees)
        primaryRMS = SlidingRMS(windowDuration: rmsWindowDuration)
        discriminatorRMS = SlidingRMS(windowDuration: rmsWindowDuration)
        self.calibrationScale = calibrationScale
    }

    public func ingest(_ sample: MotionSample) -> TurbulenceSample {
        let gateOpen = attitudeGate.evaluate(sample.attitude)
        let vertical = WorldFrameAcceleration.verticalComponent(
            userAcceleration: sample.userAcceleration, gravity: sample.gravity
        )

        // Both filters process every sample regardless of gate state -- an IIR
        // filter's internal state needs continuous input to stay settled. Skipping
        // samples during a gated-out period would leave it stale and produce a
        // transient/discontinuity when the gate reopens.
        let primaryFiltered = primaryFilter.process(vertical)
        let discriminatorFiltered = discriminatorFilter.process(vertical)

        guard gateOpen else {
            // Handling motion likely contaminates the filtered signal too -- don't
            // expose it for burst-triggering purposes either, or "pick the phone up"
            // could itself trigger burst-rate logging.
            return TurbulenceSample(
                timestamp: sample.timestamp, edrCubeRoot: nil, attitudeGateOpen: false,
                discriminatorRMS: nil, filteredVerticalAcceleration: nil
            )
        }

        let primaryRMSValue = primaryRMS.insert(sample.timestamp, primaryFiltered)
        let discriminatorRMSValue = discriminatorRMS.insert(sample.timestamp, discriminatorFiltered)

        return TurbulenceSample(
            timestamp: sample.timestamp,
            edrCubeRoot: primaryRMSValue * calibrationScale,
            attitudeGateOpen: true,
            discriminatorRMS: discriminatorRMSValue,
            filteredVerticalAcceleration: primaryFiltered
        )
    }
}
