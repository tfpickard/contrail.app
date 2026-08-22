import Foundation
import Testing
@testable import ContrailAnalytics

struct ForecastSkillCompilerTests {
    @Test func returnsNilWhenNoFlightHasPairedData() {
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [makeSample(t: Date(timeIntervalSince1970: 0), edr: 0.3)]
        )
        #expect(ForecastSkillCompiler.compile(from: [flight]) == nil)
    }

    @Test func computesBiasAsMeanSignedResidual() throws {
        let base = Date(timeIntervalSince1970: 0)
        // Consistently measured 0.2 rougher than forecast.
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [
                makeSample(t: base, edr: 0.5, forecast: 0.3),
                makeSample(t: base.addingTimeInterval(60), edr: 0.7, forecast: 0.5),
            ]
        )
        let score = try #require(ForecastSkillCompiler.compile(from: [flight]))
        #expect(score.pairedSampleCount == 2)
        #expect(abs(score.bias - 0.2) < 0.001)
        #expect(abs(score.meanAbsoluteError - 0.2) < 0.001)
        #expect(abs(score.rootMeanSquareError - 0.2) < 0.001)
    }

    @Test func perfectCorrelationWhenMeasuredTracksForecastLinearly() throws {
        let base = Date(timeIntervalSince1970: 0)
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: (0..<10).map { i in
                makeSample(
                    t: base.addingTimeInterval(Double(i) * 60),
                    edr: Double(i) * 0.1, forecast: Double(i) * 0.1 - 0.05
                )
            }
        )
        let score = try #require(ForecastSkillCompiler.compile(from: [flight]))
        #expect(score.correlation.map { abs($0 - 1.0) < 0.0001 } == true)
    }

    @Test func correlationIsNilWhenForecastHasNoVariance() throws {
        let base = Date(timeIntervalSince1970: 0)
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [
                makeSample(t: base, edr: 0.1, forecast: 0.5),
                makeSample(t: base.addingTimeInterval(60), edr: 0.9, forecast: 0.5),
            ]
        )
        let score = try #require(ForecastSkillCompiler.compile(from: [flight]))
        #expect(score.correlation == nil)
    }

    @Test func pairsAcrossMultipleFlights() throws {
        let base = Date(timeIntervalSince1970: 0)
        let flightA = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [makeSample(t: base, edr: 0.5, forecast: 0.4)]
        )
        let flightB = AnalyzedFlight(
            manifest: makeManifest(number: "UA2", date: "2026-08-08"),
            records: [makeSample(t: base, edr: 0.3, forecast: 0.4)]
        )
        let score = try #require(ForecastSkillCompiler.compile(from: [flightA, flightB]))
        #expect(score.pairedSampleCount == 2)
        #expect(abs(score.bias) < 0.001) // +0.1 and -0.1 average to zero
    }
}
