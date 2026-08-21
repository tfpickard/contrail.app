import Foundation
import Testing
import ContrailCore
import ContrailGeo
@testable import ContrailForecast

struct GTGForecastClientTests {
    private func makePlan() throws -> RouteForecastPlan {
        let flightPlan = try FlightPlan(
            flightNumber: "UA1234",
            origin: Coordinate(latitude: 39.8617, longitude: -104.6731),
            destination: Coordinate(latitude: 33.9416, longitude: -118.4085),
            scheduledDeparture: Date(timeIntervalSince1970: 1_755_640_000),
            scheduledArrival: Date(timeIntervalSince1970: 1_755_648_000),
            aircraftICAOType: nil, aircraftRegistration: nil
        )
        return try RouteForecastPlan(
            flightPlan: flightPlan, waypointSpacingMetres: 500_000, cruiseAltitudeMetres: 11_582,
            times: [Date(timeIntervalSince1970: 1_755_640_000), Date(timeIntervalSince1970: 1_755_648_000)]
        )
    }

    @Test func buildsARequestMatchingGribStreamsDocumentedShape() throws {
        let plan = try makePlan()
        let request = try GTGForecastClient.buildRequest(for: plan, apiToken: "test-token-123")

        #expect(request.httpMethod == "POST")
        #expect(request.url == GTGForecastClient.defaultEndpoint)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let coordinates = try #require(json["coordinates"] as? [[String: Any]])
        #expect(coordinates.count == plan.waypoints.count)
        #expect(coordinates[0]["lat"] as? Double == plan.waypoints[0].coordinate.latitude)

        let variables = try #require(json["variables"] as? [[String: Any]])
        #expect(variables.count == plan.levelsMetres.count)
        #expect(variables.allSatisfy { ($0["name"] as? String) == "CATEDR" })

        let times = try #require(json["timesList"] as? [String])
        #expect(times.count == 2)
    }

    @Test func parsesARealisticFixtureResponseIntoForecastSamples() throws {
        let plan = try makePlan()
        let level = plan.levelsMetres.sorted()[0]
        let alias = GTGForecastClient.levelAlias(level)
        let time = plan.times[0]
        let isoFormatter = ISO8601DateFormatter()

        // Shaped exactly per this client's own assumed schema: lat/lon/forecasted_time
        // plus one numeric column per requested (aliased) variable.
        let fixtureJSON = """
        [
          {
            "forecasted_at": "\(isoFormatter.string(from: time))",
            "forecasted_time": "\(isoFormatter.string(from: time))",
            "lat": \(plan.waypoints[0].coordinate.latitude),
            "lon": \(plan.waypoints[0].coordinate.longitude),
            "name": "wp0",
            "\(alias)": 0.15
          }
        ]
        """
        let samples = try GTGForecastClient.parse(Data(fixtureJSON.utf8), plan: plan)
        #expect(samples.count == 1)
        let sample = try #require(samples.first)
        #expect(abs(sample.coordinate.latitude - plan.waypoints[0].coordinate.latitude) < 0.0001)
        #expect(abs(sample.altitudeMetres - level) < 1)
        #expect(sample.edrCubeRoot == 0.15)
    }

    @Test func skipsRowsMissingRequiredFieldsRatherThanThrowing() throws {
        let plan = try makePlan()
        let fixtureJSON = """
        [
          {"lat": 39.0, "lon": -104.0},
          {"forecasted_time": "not-a-real-date", "lat": 39.0, "lon": -104.0}
        ]
        """
        let samples = try GTGForecastClient.parse(Data(fixtureJSON.utf8), plan: plan)
        #expect(samples.isEmpty)
    }

    @Test func throwsOnCompletelyMalformedResponseBody() throws {
        let plan = try makePlan()
        #expect(throws: GTGForecastClient.ResponseError.self) {
            _ = try GTGForecastClient.parse(Data("not json at all".utf8), plan: plan)
        }
    }
}
