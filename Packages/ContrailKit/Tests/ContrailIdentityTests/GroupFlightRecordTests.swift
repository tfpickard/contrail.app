import Foundation
import Testing
import ContrailCore
import ContrailLog
@testable import ContrailIdentity

private func channel<T: Sendable & Codable & Equatable>(_ value: T?, source: ChannelSource = .derived) -> Channel<T> {
    Channel(value: value, source: source)
}

private func makeSample(t: Date, edr: Double? = nil) -> LogRecord {
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
            edrCubeRoot: channel(edr), forecastEdrCubeRoot: .unavailable, attitudeGateOpen: .unavailable
        ),
        route: RouteRelative(
            alongTrackFlown: .unavailable, alongTrackRemaining: .unavailable,
            crossTrackError: .unavailable, fractionalProgress: .unavailable,
            nearestCity: .unavailable, eta: .unavailable
        ),
        phase: channel(FlightPhase.cruise)
    )
    return LogRecord(output: output)
}

private func makeManifest(number: String, date: String) -> FlightManifest {
    FlightManifest(
        flightID: "\(number)-\(date)",
        app: .init(version: "1.0.0", build: "1", phase: "2.0"),
        device: .init(model: "iPhone17,1", os: "18.6"),
        resolution: .init(provider: "manual", resolvedAt: Date(timeIntervalSince1970: 0)),
        flight: .init(
            number: number, date: date,
            origin: .init(
                icao: "KDEN", iata: nil, coordinate: Coordinate(latitude: 0, longitude: 0),
                elevation: nil, timezone: nil
            ),
            destination: .init(
                icao: "KLAX", iata: nil, coordinate: Coordinate(latitude: 0, longitude: 0),
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

struct FlightExportPackageTests {
    @Test func encodedRoundTripsThroughDecode() throws {
        let package = FlightExportPackage(
            participantName: "Tom", manifest: makeManifest(number: "UA1", date: "2026-08-20"),
            records: [makeSample(t: Date(timeIntervalSince1970: 0), edr: 0.4)]
        )
        let data = try package.encoded()
        let decoded = try FlightExportPackage.decode(data)
        #expect(decoded == package)
    }
}

struct GroupFlightMatcherTests {
    @Test func sameNumberAndDateMatch() {
        let a = makeManifest(number: "UA1", date: "2026-08-20")
        let b = makeManifest(number: "UA1", date: "2026-08-20")
        #expect(GroupFlightMatcher.sameFlight(a, b))
    }

    @Test func differentDateDoesNotMatch() {
        let a = makeManifest(number: "UA1", date: "2026-08-20")
        let b = makeManifest(number: "UA1", date: "2026-08-21")
        #expect(!GroupFlightMatcher.sameFlight(a, b))
    }
}

struct GroupFlightBuilderTests {
    @Test func buildsFromTwoMatchingPackages() throws {
        let mine = FlightExportPackage(
            participantName: "Tom", manifest: makeManifest(number: "UA1", date: "2026-08-20"), records: []
        )
        let theirs = FlightExportPackage(
            participantName: "Sam", manifest: makeManifest(number: "UA1", date: "2026-08-20"), records: []
        )
        let record = try GroupFlightBuilder.build(from: [mine, theirs])
        #expect(record.participants.count == 2)
    }

    @Test func rejectsASingleParticipant() {
        let mine = FlightExportPackage(
            participantName: "Tom", manifest: makeManifest(number: "UA1", date: "2026-08-20"), records: []
        )
        #expect {
            try GroupFlightBuilder.build(from: [mine])
        } throws: { error in
            (error as? GroupFlightError) == .tooFewParticipants
        }
    }

    @Test func rejectsMismatchedFlights() {
        let mine = FlightExportPackage(
            participantName: "Tom", manifest: makeManifest(number: "UA1", date: "2026-08-20"), records: []
        )
        let strangerOnADifferentFlight = FlightExportPackage(
            participantName: "Sam", manifest: makeManifest(number: "DL9", date: "2026-08-20"), records: []
        )
        #expect(throws: (any Error).self) {
            try GroupFlightBuilder.build(from: [mine, strangerOnADifferentFlight])
        }
    }
}

struct GroupTurbulenceComparisonTests {
    @Test func emptyRecordProducesNoPoints() throws {
        let mine = FlightExportPackage(
            participantName: "Tom", manifest: makeManifest(number: "UA1", date: "2026-08-20"), records: []
        )
        let theirs = FlightExportPackage(
            participantName: "Sam", manifest: makeManifest(number: "UA1", date: "2026-08-20"), records: []
        )
        let record = try GroupFlightBuilder.build(from: [mine, theirs])
        #expect(GroupTurbulenceComparison.compare(record).isEmpty)
    }

    @Test func bucketsAndAveragesEachParticipantSeparately() throws {
        let base = Date(timeIntervalSince1970: 0)
        let mine = FlightExportPackage(
            participantName: "Tom", manifest: makeManifest(number: "UA1", date: "2026-08-20"),
            records: [
                makeSample(t: base, edr: 0.2),
                makeSample(t: base.addingTimeInterval(10), edr: 0.4),
            ]
        )
        let theirs = FlightExportPackage(
            participantName: "Sam", manifest: makeManifest(number: "UA1", date: "2026-08-20"),
            records: [
                makeSample(t: base.addingTimeInterval(5), edr: 0.9),
            ]
        )
        let record = try GroupFlightBuilder.build(from: [mine, theirs])
        let points = GroupTurbulenceComparison.compare(record, bucketSeconds: 30)

        #expect(points.count == 1)
        let point = try #require(points.first)
        // Tom's two samples in the same 30s bucket average to 0.3.
        #expect(point.values["Tom"].map { abs($0 - 0.3) < 0.001 } == true)
        #expect(point.values["Sam"].map { abs($0 - 0.9) < 0.001 } == true)
    }

    @Test func participantWithNoTurbulenceDataInABucketHasNoEntry() throws {
        let base = Date(timeIntervalSince1970: 0)
        let mine = FlightExportPackage(
            participantName: "Tom", manifest: makeManifest(number: "UA1", date: "2026-08-20"),
            records: [makeSample(t: base, edr: 0.5)]
        )
        // Sam has a sample in the flight but with no EDR value at all -- distinct
        // from having no samples in this bucket.
        let theirs = FlightExportPackage(
            participantName: "Sam", manifest: makeManifest(number: "UA1", date: "2026-08-20"),
            records: [makeSample(t: base, edr: nil)]
        )
        let record = try GroupFlightBuilder.build(from: [mine, theirs])
        let points = GroupTurbulenceComparison.compare(record, bucketSeconds: 30)

        #expect(points.count == 1)
        #expect(points[0].values["Tom"] != nil)
        #expect(points[0].values["Sam"] == nil)
    }
}
