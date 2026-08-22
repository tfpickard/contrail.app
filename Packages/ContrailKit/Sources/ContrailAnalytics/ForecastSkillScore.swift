import Foundation

/// ROADMAP Phase 4, verbatim: "you have paired predicted and measured turbulence
/// for every sample of every flight. That is a verification dataset. Compute GTG's
/// actual skill against your own measurements. Nobody has this for their own
/// flying." §4.3 already computes the per-sample residual live; this is that same
/// residual, aggregated across the whole corpus into the standard forecast-
/// verification metrics.
public struct ForecastSkillScore: Sendable, Equatable {
    public let pairedSampleCount: Int
    /// Mean |measured − forecast| -- typical error magnitude, always ≥ 0.
    public let meanAbsoluteError: Double
    /// Mean (measured − forecast) -- systematic bias. Positive means GTG
    /// consistently under-predicts your measured turbulence; negative means it
    /// over-predicts.
    public let bias: Double
    public let rootMeanSquareError: Double
    /// Pearson correlation between measured and forecast, in [-1, 1]. `nil` when
    /// either series has zero variance (e.g. every forecast value identical), where
    /// correlation is mathematically undefined, not zero.
    public let correlation: Double?

    public init(
        pairedSampleCount: Int, meanAbsoluteError: Double, bias: Double,
        rootMeanSquareError: Double, correlation: Double?
    ) {
        self.pairedSampleCount = pairedSampleCount
        self.meanAbsoluteError = meanAbsoluteError
        self.bias = bias
        self.rootMeanSquareError = rootMeanSquareError
        self.correlation = correlation
    }
}

public enum ForecastSkillCompiler {
    /// `nil` when the corpus has no paired samples at all -- no flight ever fetched
    /// a forecast, or none overlapped a measurement. Distinct from a score of zero.
    public static func compile(from flights: [AnalyzedFlight]) -> ForecastSkillScore? {
        var measured: [Double] = []
        var forecast: [Double] = []

        for flight in flights {
            for sample in flight.samples {
                if let m = sample.turbulence.edrCubeRoot.value, let f = sample.turbulence.forecastEdrCubeRoot.value {
                    measured.append(m)
                    forecast.append(f)
                }
            }
        }

        guard !measured.isEmpty else { return nil }
        let n = Double(measured.count)
        let residuals = zip(measured, forecast).map { $0 - $1 }

        let bias = residuals.reduce(0, +) / n
        let meanAbsoluteError = residuals.reduce(0) { $0 + abs($1) } / n
        let rootMeanSquareError = (residuals.reduce(0) { $0 + $1 * $1 } / n).squareRoot()

        return ForecastSkillScore(
            pairedSampleCount: measured.count,
            meanAbsoluteError: meanAbsoluteError,
            bias: bias,
            rootMeanSquareError: rootMeanSquareError,
            correlation: pearsonCorrelation(measured, forecast)
        )
    }

    private static func pearsonCorrelation(_ x: [Double], _ y: [Double]) -> Double? {
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n
        var covariance = 0.0, varianceX = 0.0, varianceY = 0.0
        for (xi, yi) in zip(x, y) {
            let dx = xi - meanX, dy = yi - meanY
            covariance += dx * dy
            varianceX += dx * dx
            varianceY += dy * dy
        }
        guard varianceX > 0, varianceY > 0 else { return nil }
        return covariance / (varianceX.squareRoot() * varianceY.squareRoot())
    }
}
