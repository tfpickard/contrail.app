import Foundation
import ContrailCore
import ContrailLog
@testable import ContrailAnalytics

func channel<T: Sendable & Codable & Equatable>(_ value: T?, source: ChannelSource = .derived) -> Channel<T> {
    Channel(value: value, source: source)
}

func makeSample(
    t: Date,
    position: Coordinate? = nil, altitude: Double? = nil,
    edr: Double? = nil, forecast: Double? = nil,
    alongTrackFlown: Double? = nil, crossTrackError: Double? = nil
) -> LogRecord {
    let output = EstimatorOutput(
        t: t, uptime: t.timeIntervalSince1970,
        position: PositionEstimate(
            fused: channel(position), confidenceRadius: .unavailable, gnss: .unavailable, deadReckoned: .unavailable,
            horizontalAccuracy: .unavailable, verticalAccuracy: .unavailable, timeSinceValidFix: .unavailable,
            altitudeGPS: channel(altitude)
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
            crossTrackError: channel(crossTrackError), fractionalProgress: .unavailable,
            nearestCity: .unavailable, eta: .unavailable
        ),
        phase: channel(FlightPhase.cruise)
    )
    return LogRecord(output: output)
}

func makeManifest(
    number: String, date: String, origin: String = "KDEN", destination: String = "KLAX",
    aircraftType: String? = nil, seatPosition: SeatPosition? = nil
) -> FlightManifest {
    FlightManifest(
        flightID: "\(number)-\(date)",
        app: .init(version: "1.0.0", build: "1", phase: "4.0"),
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
            aircraft: .init(icaoType: aircraftType, registration: nil),
            filedRoute: nil,
            seatPosition: seatPosition
        ),
        assets: [],
        forecast: nil,
        sensorSource: "replay"
    )
}
