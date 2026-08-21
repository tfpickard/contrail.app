import Foundation
import Testing
import ContrailCore
import ContrailGeo
@testable import ContrailForecast

struct RouteForecastPlanTests {
    private func makePlan() throws -> FlightPlan {
        try FlightPlan(
            flightNumber: "UA1234",
            origin: Coordinate(latitude: 39.8617, longitude: -104.6731), // KDEN
            destination: Coordinate(latitude: 33.9416, longitude: -118.4085), // KLAX
            scheduledDeparture: Date(timeIntervalSince1970: 1_755_640_000),
            scheduledArrival: Date(timeIntervalSince1970: 1_755_648_000),
            aircraftICAOType: "B738", aircraftRegistration: nil
        )
    }

    @Test func generatesWaypointsAtTheRequestedSpacingPlusTheDestination() throws {
        let plan = try makePlan()
        let flightPlan = plan
        let forecastPlan = try RouteForecastPlan(
            flightPlan: flightPlan, waypointSpacingMetres: 200_000, // 200 km apart
            cruiseAltitudeMetres: 11_000, times: [Date()]
        )
        // DEN-LAX is roughly 1340 km -> 200 km spacing gives 6 interior points (0,
        // 200, ..., 1200 km) plus the destination itself appended.
        #expect(forecastPlan.waypoints.count >= 6)
        #expect(forecastPlan.waypoints.first?.alongTrackDistance == 0)
        #expect(forecastPlan.waypoints.last?.alongTrackDistance == flightPlan.totalDistance)
        // Strictly increasing along-track distance.
        for i in 1..<forecastPlan.waypoints.count {
            #expect(forecastPlan.waypoints[i].alongTrackDistance > forecastPlan.waypoints[i - 1].alongTrackDistance)
        }
    }

    @Test func waypointCoordinatesLieOnTheRealGreatCircleRoute() throws {
        let flightPlan = try makePlan()
        let forecastPlan = try RouteForecastPlan(
            flightPlan: flightPlan, waypointSpacingMetres: 500_000, cruiseAltitudeMetres: 11_000, times: [Date()]
        )
        for waypoint in forecastPlan.waypoints {
            let expected = try flightPlan.position(atAlongTrackDistance: waypoint.alongTrackDistance)
            #expect(abs(waypoint.coordinate.latitude - expected.latitude) < 0.0001)
            #expect(abs(waypoint.coordinate.longitude - expected.longitude) < 0.0001)
        }
    }

    @Test func rejectsNonPositiveSpacing() throws {
        let flightPlan = try makePlan()
        #expect(throws: RouteForecastPlan.PlanError.invalidSpacing) {
            _ = try RouteForecastPlan(
                flightPlan: flightPlan, waypointSpacingMetres: 0, cruiseAltitudeMetres: 11_000, times: [Date()]
            )
        }
    }

    @Test func levelsBracketFromGroundUpThroughCruise() throws {
        let flightPlan = try makePlan()
        let forecastPlan = try RouteForecastPlan(
            flightPlan: flightPlan, cruiseAltitudeMetres: 11_582, // ~FL380
            times: [Date()]
        )
        #expect(forecastPlan.levelsMetres.min()! < 1_000) // FL010 near the bottom
        #expect(forecastPlan.levelsMetres.max()! >= 11_582) // covers cruise
    }
}
