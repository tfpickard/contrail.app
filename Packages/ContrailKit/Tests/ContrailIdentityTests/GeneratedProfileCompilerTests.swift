import Foundation
import Testing
import ContrailCore
import ContrailLog
@testable import ContrailIdentity

private func channel<T: Sendable & Codable & Equatable>(_ value: T?, source: ChannelSource = .derived) -> Channel<T> {
    Channel(value: value, source: source)
}

private func makeSample(
    t: Date, phase: FlightPhase, alongTrackFlown: Double,
    edr: Double? = nil, forecast: Double? = nil, scheduleDelta: Double? = nil
) -> LogRecord {
    let output = EstimatorOutput(
        t: t, uptime: t.timeIntervalSince1970,
        position: PositionEstimate(
            fused: .unavailable, confidenceRadius: .unavailable, gnss: .unavailable, deadReckoned: .unavailable,
            horizontalAccuracy: .unavailable, verticalAccuracy: .unavailable, timeSinceValidFix: .unavailable,
            altitudeGPS: .unavailable
        ),
        motion: MotionEstimate(
            groundspeed: .unavailable, trueCourse: .unavailable, trackAngleRate: .unavailable,
            verticalSpeed: .unavailable, longitudinalAcceleration: .unavailable,
            clSpeed: .unavailable, clCourse: .unavailable
        ),
        cabin: CabinEnvironment(
            pressure: .unavailable, pressureAltitude: .unavailable, pressurizationRate: .unavailable
        ),
        turbulence: TurbulenceEstimate(
            edrCubeRoot: channel(edr), forecastEdrCubeRoot: channel(forecast, source: .forecast),
            attitudeGateOpen: .unavailable
        ),
        route: RouteRelative(
            alongTrackFlown: channel(alongTrackFlown), alongTrackRemaining: .unavailable,
            crossTrackError: .unavailable, fractionalProgress: .unavailable, nearestCity: .unavailable,
            eta: scheduleDelta.map { channel(ETAEstimate(arrival: t, sigma: 60, scheduleDelta: $0)) } ?? .unavailable
        ),
        phase: channel(phase)
    )
    return LogRecord(output: output)
}

private func makeManifest(number: String, date: String, origin: String, destination: String) -> FlightManifest {
    FlightManifest(
        flightID: "\(number)-\(date)",
        app: .init(version: "1.0.0", build: "1", phase: "2.0"),
        device: .init(model: "iPhone17,1", os: "18.6"),
        resolution: .init(provider: "manual", resolvedAt: Date(timeIntervalSince1970: 0)),
        flight: .init(
            number: number, date: date,
            origin: .init(
                icao: origin, iata: nil, coordinate: Coordinate(latitude: 0, longitude: 0),
                elevation: nil, timezone: nil
            ),
            destination: .init(
                icao: destination, iata: nil, coordinate: Coordinate(latitude: 0, longitude: 0),
                elevation: nil, timezone: nil
            ),
            scheduled: .init(
                departure: Date(timeIntervalSince1970: 0), arrival: Date(timeIntervalSince1970: 3600),
                blockTime: 3600
            ),
            aircraft: .init(icaoType: nil, registration: nil),
            filedRoute: nil
        ),
        assets: [],
        forecast: nil,
        sensorSource: "replay"
    )
}

struct GeneratedProfileCompilerTests {
    @Test func emptyInputReturnsEmpty() {
        #expect(GeneratedProfileCompiler.compile(from: []) == .empty)
    }

    @Test func flightWithNoSampleRecordsIsIgnored() {
        let manifest = makeManifest(number: "UA1", date: "2026-08-20", origin: "KDEN", destination: "KLAX")
        let flight = GeneratedProfileCompiler.FlightData(manifest: manifest, records: [])
        #expect(GeneratedProfileCompiler.compile(from: [flight]) == .empty)
    }

    @Test func computesFlightsLoggedAndDistanceFromFinalAlongTrackFlown() {
        let base = Date(timeIntervalSince1970: 0)
        let manifest = makeManifest(number: "UA1", date: "2026-08-20", origin: "KDEN", destination: "KLAX")
        let records = [
            makeSample(t: base, phase: .cruise, alongTrackFlown: 100_000),
            makeSample(t: base.addingTimeInterval(600), phase: .cruise, alongTrackFlown: 200_000),
        ]
        let flight = GeneratedProfileCompiler.FlightData(manifest: manifest, records: records)
        let stats = GeneratedProfileCompiler.compile(from: [flight])

        #expect(stats.flightsLogged == 1)
        #expect(abs(stats.totalDistanceNauticalMiles - 200_000 / 1852.0) < 0.001)
    }

    @Test func hoursAtAltitudeExcludesLeadingAndTrailingTaxiSamples() {
        let base = Date(timeIntervalSince1970: 0)
        let manifest = makeManifest(number: "UA1", date: "2026-08-20", origin: "KDEN", destination: "KLAX")
        let records = [
            makeSample(t: base, phase: .taxi, alongTrackFlown: 0),
            makeSample(t: base.addingTimeInterval(600), phase: .takeoff, alongTrackFlown: 1_000),
            makeSample(t: base.addingTimeInterval(4_200), phase: .cruise, alongTrackFlown: 100_000),
            makeSample(t: base.addingTimeInterval(7_800), phase: .taxi, alongTrackFlown: 150_000),
        ]
        let flight = GeneratedProfileCompiler.FlightData(manifest: manifest, records: records)
        let stats = GeneratedProfileCompiler.compile(from: [flight])

        // Airborne window is takeoff (600s) through cruise (4200s) -- taxi samples
        // at both ends are excluded, so this is 1 hour, not 2h10m end-to-end.
        #expect(abs(stats.hoursAtAltitude - 1.0) < 0.001)
    }

    @Test func identifiesRoughestAndSmoothestRoutesByPerFlightAverageEDR() {
        let base = Date(timeIntervalSince1970: 0)
        let smoothFlight = GeneratedProfileCompiler.FlightData(
            manifest: makeManifest(number: "UA1", date: "2026-08-20", origin: "KDEN", destination: "KLAX"),
            records: [
                makeSample(t: base, phase: .cruise, alongTrackFlown: 100_000, edr: 0.1),
                makeSample(t: base.addingTimeInterval(60), phase: .cruise, alongTrackFlown: 110_000, edr: 0.1),
            ]
        )
        let roughFlight = GeneratedProfileCompiler.FlightData(
            manifest: makeManifest(number: "UA2", date: "2026-08-21", origin: "KJFK", destination: "KMIA"),
            records: [
                makeSample(t: base, phase: .cruise, alongTrackFlown: 100_000, edr: 0.9),
                makeSample(t: base.addingTimeInterval(60), phase: .cruise, alongTrackFlown: 110_000, edr: 0.9),
            ]
        )
        let stats = GeneratedProfileCompiler.compile(from: [smoothFlight, roughFlight])

        #expect(stats.roughestRoute?.route == "KJFK-KMIA")
        #expect(stats.smoothestRoute?.route == "KDEN-KLAX")
        #expect(stats.personalAverageEDRCubeRoot.map { abs($0 - 0.5) < 0.001 } == true)
    }

    @Test func turbulenceLuckDeltaAveragesMeasuredMinusForecastResiduals() {
        let base = Date(timeIntervalSince1970: 0)
        let manifest = makeManifest(number: "UA1", date: "2026-08-20", origin: "KDEN", destination: "KLAX")
        // Consistently measured 0.2 rougher than forecast -- a "cursed" flight.
        let records = [
            makeSample(t: base, phase: .cruise, alongTrackFlown: 100_000, edr: 0.5, forecast: 0.3),
            makeSample(t: base.addingTimeInterval(60), phase: .cruise, alongTrackFlown: 110_000, edr: 0.7, forecast: 0.5),
        ]
        let flight = GeneratedProfileCompiler.FlightData(manifest: manifest, records: records)
        let stats = GeneratedProfileCompiler.compile(from: [flight])

        #expect(stats.turbulenceLuckDelta.map { abs($0 - 0.2) < 0.001 } == true)
    }

    @Test func noForecastDataLeavesLuckDeltaNil() {
        let base = Date(timeIntervalSince1970: 0)
        let manifest = makeManifest(number: "UA1", date: "2026-08-20", origin: "KDEN", destination: "KLAX")
        let records = [makeSample(t: base, phase: .cruise, alongTrackFlown: 100_000, edr: 0.5)]
        let flight = GeneratedProfileCompiler.FlightData(manifest: manifest, records: records)
        #expect(GeneratedProfileCompiler.compile(from: [flight]).turbulenceLuckDelta == nil)
    }

    @Test func averageScheduleDeltaUsesEachFlightsFinalSample() {
        let base = Date(timeIntervalSince1970: 0)
        let flightA = GeneratedProfileCompiler.FlightData(
            manifest: makeManifest(number: "UA1", date: "2026-08-20", origin: "KDEN", destination: "KLAX"),
            records: [
                makeSample(t: base, phase: .cruise, alongTrackFlown: 100_000, scheduleDelta: -600),
                makeSample(t: base.addingTimeInterval(60), phase: .taxi, alongTrackFlown: 110_000, scheduleDelta: -300),
            ]
        )
        let flightB = GeneratedProfileCompiler.FlightData(
            manifest: makeManifest(number: "UA2", date: "2026-08-21", origin: "KJFK", destination: "KMIA"),
            records: [
                makeSample(t: base, phase: .cruise, alongTrackFlown: 100_000, scheduleDelta: 900),
            ]
        )
        let stats = GeneratedProfileCompiler.compile(from: [flightA, flightB])

        // (-300 + 900) / 2 = 300
        #expect(stats.averageScheduleDeltaSeconds.map { abs($0 - 300) < 0.001 } == true)
    }
}
