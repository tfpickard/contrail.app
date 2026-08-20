import Foundation

/// A second-order (biquad) IIR digital filter, Direct Form I. The building block for
/// both the high-pass and low-pass stages of `CascadedBandPassFilter` — a band-pass
/// this wide (0.1–10 Hz) is built as a cascade of the two, not a single resonant
/// band-pass biquad, which is the wrong shape for a wide, flat passband (see
/// `CascadedBandPassFilter`'s own doc comment).
struct Biquad {
    private let b0, b1, b2, a1, a2: Double
    private var x1 = 0.0, x2 = 0.0
    private var y1 = 0.0, y2 = 0.0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        // Normalize so a0 == 1, per the standard Direct Form I recurrence.
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    mutating func process(_ x0: Double) -> Double {
        let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x0
        y2 = y1; y1 = y0
        return y0
    }

    /// Second-order Butterworth high-pass (Q = 1/√2, maximally flat passband).
    /// Coefficients per the RBJ "Cookbook formulae for audio EQ biquad filter
    /// coefficients" — a standard, widely-verified derivation from the analog
    /// prototype via the bilinear transform.
    static func highPass(cutoffHz: Double, sampleRateHz: Double) -> Biquad {
        let q = 1.0 / 2.0.squareRoot()
        let omega = 2 * Double.pi * cutoffHz / sampleRateHz
        let cosOmega = cos(omega)
        let alpha = sin(omega) / (2 * q)

        let b0 = (1 + cosOmega) / 2
        let b1 = -(1 + cosOmega)
        let b2 = (1 + cosOmega) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha
        return Biquad(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }

    /// Second-order Butterworth low-pass (Q = 1/√2).
    static func lowPass(cutoffHz: Double, sampleRateHz: Double) -> Biquad {
        let q = 1.0 / 2.0.squareRoot()
        let omega = 2 * Double.pi * cutoffHz / sampleRateHz
        let cosOmega = cos(omega)
        let alpha = sin(omega) / (2 * q)

        let b0 = (1 - cosOmega) / 2
        let b1 = 1 - cosOmega
        let b2 = (1 - cosOmega) / 2
        let a0 = 1 + alpha
        let a1 = -2 * cosOmega
        let a2 = 1 - alpha
        return Biquad(b0: b0, b1: b1, b2: b2, a0: a0, a1: a1, a2: a2)
    }
}
