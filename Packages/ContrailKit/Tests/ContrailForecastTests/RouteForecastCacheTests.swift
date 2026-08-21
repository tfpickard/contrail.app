import Foundation
import Testing
import ContrailCore
import ContrailGeo
@testable import ContrailForecast

struct RouteForecastCacheTests {
    private func makePlanAndCache(values: [(waypoint: Int, level: Double, time: Int, value: Double)]) throws
        -> (RouteForecastPlan, RouteForecastCache)
    {
        let flightPlan = try FlightPlan(
            flightNumber: "UA1234",
            origin: Coordinate(latitude: 39.8617, longitude: -104.6731),
            destination: Coordinate(latitude: 33.9416, longitude: -118.4085),
            scheduledDeparture: Date(timeIntervalSince1970: 0),
            scheduledArrival: Date(timeIntervalSince1970: 7200),
            aircraftICAOType: nil, aircraftRegistration: nil
        )
        let times = [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 3600)]
        let plan = try RouteForecastPlan(
            flightPlan: flightPlan, waypointSpacingMetres: flightPlan.totalDistance / 2,
            cruiseAltitudeMetres: 11_582, times: times
        )
        let sortedLevels = plan.levelsMetres.sorted()
        let samples = values.map { entry in
            ForecastSample(
                coordinate: plan.waypoints[entry.waypoint].coordinate,
                altitudeMetres: sortedLevels[Int(entry.level)],
                validTime: times[entry.time],
                edrCubeRoot: entry.value
            )
        }
        return (plan, RouteForecastCache(plan: plan, samples: samples))
    }

    @Test func exactCornerLookupReturnsExactlyWhatWasFetched() throws {
        let (plan, cache) = try makePlanAndCache(values: [(0, 0, 0, 0.42)])
        let value = cache.value(
            alongTrackFlown: plan.waypoints[0].alongTrackDistance,
            altitudeMetres: plan.levelsMetres.sorted()[0],
            time: plan.times[0]
        )
        #expect(value == 0.42)
    }

    @Test func interpolatesLinearlyBetweenTwoAltitudeLevels() throws {
        // Same waypoint/time, two adjacent levels with different values -- the
        // midpoint altitude must read exactly halfway between them. This is the
        // spec's own "altitude interpolation is not optional" requirement, checked
        // directly rather than assumed.
        let (plan, cache) = try makePlanAndCache(values: [
            (0, 0, 0, 0.0), (0, 1, 0, 1.0),
        ])
        let sortedLevels = plan.levelsMetres.sorted()
        let midAltitude = (sortedLevels[0] + sortedLevels[1]) / 2
        let value = try #require(cache.value(
            alongTrackFlown: plan.waypoints[0].alongTrackDistance, altitudeMetres: midAltitude, time: plan.times[0]
        ))
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test func interpolatesLinearlyAlongTrackBetweenWaypoints() throws {
        let (plan, cache) = try makePlanAndCache(values: [
            (0, 0, 0, 0.0), (1, 0, 0, 1.0),
        ])
        let midDistance = (plan.waypoints[0].alongTrackDistance + plan.waypoints[1].alongTrackDistance) / 2
        let value = try #require(cache.value(
            alongTrackFlown: midDistance, altitudeMetres: plan.levelsMetres.sorted()[0], time: plan.times[0]
        ))
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test func interpolatesLinearlyAcrossTime() throws {
        let (plan, cache) = try makePlanAndCache(values: [
            (0, 0, 0, 0.0), (0, 0, 1, 1.0),
        ])
        let midTime = Date(
            timeIntervalSince1970: (plan.times[0].timeIntervalSince1970 + plan.times[1].timeIntervalSince1970) / 2
        )
        let value = try #require(cache.value(
            alongTrackFlown: plan.waypoints[0].alongTrackDistance, altitudeMetres: plan.levelsMetres.sorted()[0],
            time: midTime
        ))
        #expect(abs(value - 0.5) < 0.001)
    }

    @Test func returnsNilOutsideTheFetchedRange() throws {
        let (plan, cache) = try makePlanAndCache(values: [(0, 0, 0, 0.5)])
        // Before the route even starts.
        #expect(cache.value(alongTrackFlown: -1000, altitudeMetres: plan.levelsMetres[0], time: plan.times[0]) == nil)
        // A time far past what was fetched.
        #expect(cache.value(
            alongTrackFlown: plan.waypoints[0].alongTrackDistance, altitudeMetres: plan.levelsMetres[0],
            time: Date(timeIntervalSince1970: 999_999)
        ) == nil)
    }

    @Test func returnsNilWhenARequiredCornerWasNeverFetched() throws {
        // Only one of the eight trilinear corners has real data -- the others being
        // missing must fail the lookup honestly, not silently substitute zero.
        let (plan, cache) = try makePlanAndCache(values: [(0, 0, 0, 0.5)])
        let midAltitude = (plan.levelsMetres.sorted()[0] + plan.levelsMetres.sorted()[1]) / 2
        #expect(cache.value(
            alongTrackFlown: plan.waypoints[0].alongTrackDistance, altitudeMetres: midAltitude, time: plan.times[0]
        ) == nil)
    }
}
