import Foundation
import Testing
@testable import ContrailAnalytics

struct AircraftComparisonCompilerTests {
    @Test func groupsByAircraftTypeAndPoolsSamples() {
        let base = Date(timeIntervalSince1970: 0)
        let flightA = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01", aircraftType: "B738"),
            records: [makeSample(t: base, edr: 0.2)]
        )
        let flightB = AnalyzedFlight(
            manifest: makeManifest(number: "UA2", date: "2026-08-08", aircraftType: "B738"),
            records: [makeSample(t: base, edr: 0.4)]
        )
        let flightC = AnalyzedFlight(
            manifest: makeManifest(number: "DL1", date: "2026-08-01", aircraftType: "A320"),
            records: [makeSample(t: base, edr: 0.9)]
        )
        let profiles = AircraftComparisonCompiler.compile(from: [flightA, flightB, flightC])

        #expect(profiles.map(\.group).sorted() == ["A320", "B738"])
        let b738 = profiles.first { $0.group == "B738" }
        #expect(b738?.flightCount == 2)
        #expect((b738?.distribution.mean).map { abs($0 - 0.3) < 0.001 } == true)
    }

    @Test func excludesFlightsWithNoAircraftType() {
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01", aircraftType: nil),
            records: [makeSample(t: Date(timeIntervalSince1970: 0), edr: 0.3)]
        )
        #expect(AircraftComparisonCompiler.compile(from: [flight]).isEmpty)
    }
}

struct SeatComparisonCompilerTests {
    @Test func groupsBySeatPosition() {
        let base = Date(timeIntervalSince1970: 0)
        let forward = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01", seatPosition: .forward),
            records: [makeSample(t: base, edr: 0.1)]
        )
        let aft = AnalyzedFlight(
            manifest: makeManifest(number: "UA2", date: "2026-08-01", seatPosition: .aft),
            records: [makeSample(t: base, edr: 0.6)]
        )
        let profiles = SeatComparisonCompiler.compile(from: [forward, aft])
        #expect(profiles.map(\.group).sorted() == ["Aft of wing", "Forward of wing"])
    }

    @Test func excludesFlightsWithNoSeatPositionEntered() {
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01", seatPosition: nil),
            records: [makeSample(t: Date(timeIntervalSince1970: 0), edr: 0.3)]
        )
        #expect(SeatComparisonCompiler.compile(from: [flight]).isEmpty)
    }
}
