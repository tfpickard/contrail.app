import Testing
@testable import ContrailTurbulence

struct CascadedBandPassFilterTests {
    private let sampleRate = 50.0

    // The primary 0.1-10 Hz band -- the plan's own corrected design (the spec's
    // original 3-4 Hz high-pass would have removed most of the real turbulence
    // signal, which is concentrated ~0.1-2 Hz).
    @Test func primaryBandPassesMidRangeTurbulenceFrequencies() {
        let gain = FilterTestSupport.measureGain(
            of: { CascadedBandPassFilter(lowCutoffHz: 0.1, highCutoffHz: 10, sampleRateHz: sampleRate) },
            frequencyHz: 1, sampleRateHz: sampleRate
        )
        #expect(gain > 0.9)
    }

    @Test func primaryBandAttenuatesNearDC() {
        let gain = FilterTestSupport.measureGain(
            of: { CascadedBandPassFilter(lowCutoffHz: 0.1, highCutoffHz: 10, sampleRateHz: sampleRate) },
            frequencyHz: 0.01, sampleRateHz: sampleRate,
            durationSeconds: 200, warmUpSeconds: 100
        )
        #expect(gain < 0.15)
    }

    @Test func primaryBandAttenuatesWellAboveTenHertz() {
        let gain = FilterTestSupport.measureGain(
            of: { CascadedBandPassFilter(lowCutoffHz: 0.1, highCutoffHz: 10, sampleRateHz: sampleRate) },
            frequencyHz: 22, sampleRateHz: sampleRate
        )
        #expect(gain < 0.2)
    }

    // The 5-20 Hz discriminator band.
    @Test func discriminatorBandPassesItsMidRangeAndRejectsThePrimaryBandsCenter() {
        let discriminatorGainAt10Hz = FilterTestSupport.measureGain(
            of: { CascadedBandPassFilter(lowCutoffHz: 5, highCutoffHz: 20, sampleRateHz: sampleRate) },
            frequencyHz: 10, sampleRateHz: sampleRate
        )
        #expect(discriminatorGainAt10Hz > 0.85)

        // At 1 Hz -- well inside the *primary* band's passband -- the discriminator
        // band should reject it, since the two bands exist to measure different
        // things.
        let discriminatorGainAt1Hz = FilterTestSupport.measureGain(
            of: { CascadedBandPassFilter(lowCutoffHz: 5, highCutoffHz: 20, sampleRateHz: sampleRate) },
            frequencyHz: 1, sampleRateHz: sampleRate
        )
        #expect(discriminatorGainAt1Hz < 0.2)
    }
}
