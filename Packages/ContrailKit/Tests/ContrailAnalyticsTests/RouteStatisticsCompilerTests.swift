import Foundation
import Testing
@testable import ContrailAnalytics

struct RouteStatisticsCompilerTests {
    @Test func poolsSamplesAcrossMultipleFlightsOnTheSameRoute() {
        let base = Date(timeIntervalSince1970: 0)
        let flightA = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [makeSample(t: base, edr: 0.2), makeSample(t: base.addingTimeInterval(60), edr: 0.4)]
        )
        let flightB = AnalyzedFlight(
            manifest: makeManifest(number: "UA2", date: "2026-08-08"),
            records: [makeSample(t: base, edr: 0.6)]
        )
        let stats = RouteStatisticsCompiler.compile(from: [flightA, flightB])

        #expect(stats.count == 1)
        #expect(stats[0].route == "KDEN-KLAX")
        #expect(stats[0].flightCount == 2)
        #expect(stats[0].distribution?.count == 3)
        #expect(stats[0].distribution.map { abs($0.mean - 0.4) < 0.001 } == true)
    }

    @Test func separatesDistinctRoutes() {
        let base = Date(timeIntervalSince1970: 0)
        let denLax = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01", origin: "KDEN", destination: "KLAX"),
            records: [makeSample(t: base, edr: 0.1)]
        )
        let jfkMia = AnalyzedFlight(
            manifest: makeManifest(number: "AA1", date: "2026-08-01", origin: "KJFK", destination: "KMIA"),
            records: [makeSample(t: base, edr: 0.9)]
        )
        let stats = RouteStatisticsCompiler.compile(from: [denLax, jfkMia])
        #expect(stats.map(\.route).sorted() == ["KDEN-KLAX", "KJFK-KMIA"])
    }

    @Test func bucketsByTimeOfDayAndSeason() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morningInJuly = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 8))!
        let nightInJanuary = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: 2))!

        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-07-15"),
            records: [
                makeSample(t: morningInJuly, edr: 0.2),
                makeSample(t: nightInJanuary, edr: 0.8),
            ]
        )
        let stats = RouteStatisticsCompiler.compile(from: [flight], calendar: calendar)
        let route = stats[0]

        #expect(route.byTimeOfDay[.morning].map { abs($0 - 0.2) < 0.001 } == true)
        #expect(route.byTimeOfDay[.night].map { abs($0 - 0.8) < 0.001 } == true)
        #expect(route.bySeason[.summer].map { abs($0 - 0.2) < 0.001 } == true)
        #expect(route.bySeason[.winter].map { abs($0 - 0.8) < 0.001 } == true)
    }

    @Test func flightsWithNoTurbulenceDataStillCountTowardFlightCount() {
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [makeSample(t: Date(timeIntervalSince1970: 0))]
        )
        let stats = RouteStatisticsCompiler.compile(from: [flight])
        #expect(stats[0].flightCount == 1)
        #expect(stats[0].distribution == nil)
    }
}
