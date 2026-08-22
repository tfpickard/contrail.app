import Foundation
import Testing
@testable import ContrailAnalytics

struct RouteDeviationCompilerTests {
    @Test func bucketsByAlongTrackDistance() {
        let base = Date(timeIntervalSince1970: 0)
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [
                makeSample(t: base, alongTrackFlown: 5_000, crossTrackError: 100),
                makeSample(t: base.addingTimeInterval(60), alongTrackFlown: 15_000, crossTrackError: 300),
                makeSample(t: base.addingTimeInterval(120), alongTrackFlown: 25_000, crossTrackError: -200),
            ]
        )
        let buckets = RouteDeviationCompiler.compile(for: "KDEN-KLAX", from: [flight], bucketMetres: 20_000)

        #expect(buckets.count == 2)
        #expect(buckets[0].alongTrackStartMetres == 0)
        #expect(buckets[0].sampleCount == 2)
        #expect(abs(buckets[0].meanCrossTrackErrorMetres - 200) < 0.001)
        #expect(buckets[1].alongTrackStartMetres == 20_000)
        #expect(buckets[1].sampleCount == 1)
    }

    @Test func onlyIncludesSamplesFromTheRequestedRoute() {
        let base = Date(timeIntervalSince1970: 0)
        let denLax = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01", origin: "KDEN", destination: "KLAX"),
            records: [makeSample(t: base, alongTrackFlown: 1_000, crossTrackError: 50)]
        )
        let jfkMia = AnalyzedFlight(
            manifest: makeManifest(number: "AA1", date: "2026-08-01", origin: "KJFK", destination: "KMIA"),
            records: [makeSample(t: base, alongTrackFlown: 1_000, crossTrackError: 9_999)]
        )
        let buckets = RouteDeviationCompiler.compile(for: "KDEN-KLAX", from: [denLax, jfkMia], bucketMetres: 20_000)
        #expect(buckets.count == 1)
        #expect(buckets[0].meanCrossTrackErrorMetres == 50)
    }

    @Test func maxAbsoluteCapturesTheLargestDeviationRegardlessOfSign() {
        let base = Date(timeIntervalSince1970: 0)
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [
                makeSample(t: base, alongTrackFlown: 1_000, crossTrackError: 100),
                makeSample(t: base.addingTimeInterval(60), alongTrackFlown: 2_000, crossTrackError: -500),
            ]
        )
        let buckets = RouteDeviationCompiler.compile(for: "KDEN-KLAX", from: [flight], bucketMetres: 20_000)
        #expect(buckets[0].maxAbsoluteCrossTrackErrorMetres == 500)
    }
}
