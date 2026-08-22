import Foundation
import Testing
import ContrailCore
@testable import ContrailLog

struct FlightManifestTests {
    private func makeManifest() -> FlightManifest {
        FlightManifest(
            flightID: "UA1234-2026-08-20",
            app: FlightManifest.AppInfo(version: "1.0.0", build: "142", phase: "1.0"),
            device: FlightManifest.DeviceInfo(model: "iPhone17,1", os: "18.6"),
            resolution: FlightManifest.ResolutionInfo(
                provider: "manual", resolvedAt: Date(timeIntervalSince1970: 1_755_639_000)
            ),
            flight: FlightManifest.FlightInfo(
                number: "UA1234", date: "2026-08-20",
                origin: FlightManifest.AirportInfo(
                    icao: "KDEN", iata: "DEN",
                    coordinate: Coordinate(latitude: 39.8617, longitude: -104.6731),
                    elevation: 1655, timezone: "America/Denver"
                ),
                destination: FlightManifest.AirportInfo(
                    icao: "KLAX", iata: "LAX",
                    coordinate: Coordinate(latitude: 33.9416, longitude: -118.4085),
                    elevation: 38, timezone: "America/Los_Angeles"
                ),
                scheduled: FlightManifest.ScheduledTimes(
                    departure: Date(timeIntervalSince1970: 1_755_639_600),
                    arrival: Date(timeIntervalSince1970: 1_755_648_000),
                    blockTime: 8400
                ),
                aircraft: FlightManifest.AircraftInfo(icaoType: "B738", registration: nil),
                filedRoute: nil,
                seatPosition: .overWing
            ),
            assets: [
                FlightManifest.AssetInfo(
                    kind: "basemap", id: "contrail-world-z0-6", bytes: 48_234_112,
                    sha256: "abc123", verified: true
                )
            ],
            forecast: nil,
            sensorSource: "replay"
        )
    }

    @Test func roundTripsThroughJSON() throws {
        let manifest = makeManifest()
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(FlightManifest.self, from: data)
        #expect(decoded == manifest)
    }

    @Test func forecastAndFiledRouteAreExplicitlyNullNotOmitted() throws {
        // Both fields exist in the schema from day one so 1.4/1.6 never migrate a
        // manifest -- verify they actually serialize, not just default away.
        let manifest = makeManifest()
        let data = try JSONEncoder().encode(manifest)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?.keys.contains("forecast") == true)

        let flight = object?["flight"] as? [String: Any]
        #expect(flight?.keys.contains("filedRoute") == true)
    }

    @Test func assetsListRoundTrips() throws {
        let manifest = makeManifest()
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(FlightManifest.self, from: data)
        #expect(decoded.assets.count == 1)
        #expect(decoded.assets[0].verified == true)
    }

    @Test func seatPositionRoundTripsAndSerializesAsExplicitValue() throws {
        let manifest = makeManifest()
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(FlightManifest.self, from: data)
        #expect(decoded.flight.seatPosition == .overWing)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let flight = object?["flight"] as? [String: Any]
        #expect(flight?["seatPosition"] as? String == "over_wing")
    }

    /// A manifest written before Phase 4 has no "seatPosition" key at all -- not
    /// even a null one, since the key didn't exist yet. Must still decode.
    @Test func decodingAPreSeatPositionManifestFallsBackToNil() throws {
        let manifest = makeManifest()
        var data = try JSONEncoder().encode(manifest)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var flight = object["flight"] as! [String: Any]
        flight.removeValue(forKey: "seatPosition")
        object["flight"] = flight
        data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(FlightManifest.self, from: data)
        #expect(decoded.flight.seatPosition == nil)
    }
}
