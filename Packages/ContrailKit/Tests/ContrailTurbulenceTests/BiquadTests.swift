import Testing
@testable import ContrailTurbulence

struct BiquadTests {
    private let sampleRate = 50.0

    @Test func highPassAttenuatesFrequenciesWellBelowCutoff() {
        // Cutoff 0.1 Hz; a near-DC 0.01 Hz signal (an octave and a half below) should
        // be heavily attenuated.
        let gain = FilterTestSupport.measureBiquadGain(
            { .highPass(cutoffHz: 0.1, sampleRateHz: sampleRate) },
            frequencyHz: 0.01, sampleRateHz: sampleRate,
            durationSeconds: 200, warmUpSeconds: 100
        )
        #expect(gain < 0.15)
    }

    @Test func highPassPassesFrequenciesWellAboveCutoff() {
        // Cutoff 0.1 Hz; 5 Hz is many octaves up -- should pass essentially
        // unattenuated.
        let gain = FilterTestSupport.measureBiquadGain(
            { .highPass(cutoffHz: 0.1, sampleRateHz: sampleRate) },
            frequencyHz: 5, sampleRateHz: sampleRate
        )
        #expect(gain > 0.98)
    }

    @Test func lowPassPassesFrequenciesWellBelowCutoff() {
        // Cutoff 10 Hz; 1 Hz should pass essentially unattenuated.
        let gain = FilterTestSupport.measureBiquadGain(
            { .lowPass(cutoffHz: 10, sampleRateHz: sampleRate) },
            frequencyHz: 1, sampleRateHz: sampleRate
        )
        #expect(gain > 0.98)
    }

    @Test func lowPassAttenuatesFrequenciesWellAboveCutoff() {
        // Cutoff 10 Hz; 20 Hz (one octave up) should show real attenuation for a
        // 2nd-order (12 dB/octave) Butterworth response.
        let gain = FilterTestSupport.measureBiquadGain(
            { .lowPass(cutoffHz: 10, sampleRateHz: sampleRate) },
            frequencyHz: 20, sampleRateHz: sampleRate
        )
        #expect(gain < 0.35)
    }

    @Test func gainAtCutoffIsApproximatelyMinusThreeDecibels() {
        // The defining property of a Butterworth (Q = 1/sqrt(2)) filter: gain at the
        // cutoff frequency itself is ~0.707 (-3 dB), not near 0 or near 1.
        let gain = FilterTestSupport.measureBiquadGain(
            { .lowPass(cutoffHz: 5, sampleRateHz: sampleRate) },
            frequencyHz: 5, sampleRateHz: sampleRate
        )
        #expect(abs(gain - 0.707) < 0.05)
    }
}
