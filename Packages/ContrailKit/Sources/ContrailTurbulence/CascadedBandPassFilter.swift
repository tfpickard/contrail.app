/// A band-pass filter built by cascading a high-pass into a low-pass — the right
/// construction for a *wide* passband (nearly 7 octaves for the 0.1–10 Hz primary
/// band), where a single resonant biquad band-pass would be the wrong filter shape
/// entirely: that topology has a narrow resonant peak with rolloff on both sides,
/// not a flat pass region between two independent cutoffs. Two Butterworth stages in
/// series is the standard way to get a flat-ish passband bounded by two cutoffs.
struct CascadedBandPassFilter {
    private var highPass: Biquad
    private var lowPass: Biquad

    init(lowCutoffHz: Double, highCutoffHz: Double, sampleRateHz: Double) {
        highPass = .highPass(cutoffHz: lowCutoffHz, sampleRateHz: sampleRateHz)
        lowPass = .lowPass(cutoffHz: highCutoffHz, sampleRateHz: sampleRateHz)
    }

    mutating func process(_ sample: Double) -> Double {
        lowPass.process(highPass.process(sample))
    }
}
