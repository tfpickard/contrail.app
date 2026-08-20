import Foundation
@testable import ContrailTurbulence

/// Measures a filter's steady-state gain at a given frequency by feeding it several
/// seconds of a unit-amplitude sine wave, discarding an initial warm-up period (so
/// the IIR filter's transient response doesn't contaminate the measurement), and
/// comparing output RMS to input RMS. This is the actual way to verify a digital
/// filter's coefficients are correct — measuring its real behavior against a known
/// signal, not just checking the code compiles.
enum FilterTestSupport {
    static func measureGain(
        of makeFilter: () -> CascadedBandPassFilter,
        frequencyHz: Double,
        sampleRateHz: Double,
        durationSeconds: Double = 10,
        warmUpSeconds: Double = 3
    ) -> Double {
        var filter = makeFilter()
        let sampleCount = Int(durationSeconds * sampleRateHz)
        let warmUpCount = Int(warmUpSeconds * sampleRateHz)

        var inputSumSquares = 0.0
        var outputSumSquares = 0.0
        var measuredCount = 0

        for n in 0..<sampleCount {
            let t = Double(n) / sampleRateHz
            let input = sin(2 * Double.pi * frequencyHz * t)
            let output = filter.process(input)

            if n >= warmUpCount {
                inputSumSquares += input * input
                outputSumSquares += output * output
                measuredCount += 1
            }
        }

        let inputRMS = (inputSumSquares / Double(measuredCount)).squareRoot()
        let outputRMS = (outputSumSquares / Double(measuredCount)).squareRoot()
        return outputRMS / inputRMS
    }

    static func measureBiquadGain(
        _ makeBiquad: () -> Biquad,
        frequencyHz: Double,
        sampleRateHz: Double,
        durationSeconds: Double = 10,
        warmUpSeconds: Double = 3
    ) -> Double {
        var biquad = makeBiquad()
        let sampleCount = Int(durationSeconds * sampleRateHz)
        let warmUpCount = Int(warmUpSeconds * sampleRateHz)

        var inputSumSquares = 0.0
        var outputSumSquares = 0.0
        var measuredCount = 0

        for n in 0..<sampleCount {
            let t = Double(n) / sampleRateHz
            let input = sin(2 * Double.pi * frequencyHz * t)
            let output = biquad.process(input)

            if n >= warmUpCount {
                inputSumSquares += input * input
                outputSumSquares += output * output
                measuredCount += 1
            }
        }

        let inputRMS = (inputSumSquares / Double(measuredCount)).squareRoot()
        let outputRMS = (outputSumSquares / Double(measuredCount)).squareRoot()
        return outputRMS / inputRMS
    }
}
