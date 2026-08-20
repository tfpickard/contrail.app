import Foundation
import Testing
import ContrailCore
@testable import ContrailGeo

struct GreatCircleTrackTests {
    // A simple eastbound route along the equator: easy to reason about by hand.
    private let start = Coordinate(latitude: 0, longitude: 0)
    private let end = Coordinate(latitude: 0, longitude: 10)

    @Test func pointExactlyOnRouteHasZeroCrossTrack() {
        let midpoint = Coordinate(latitude: 0, longitude: 5)
        let geometry = GreatCircleTrack.relativeGeometry(of: midpoint, start: start, end: end)
        #expect(abs(geometry.crossTrackError) < 1.0) // metres
        #expect(geometry.alongTrackFromStart > 0)
    }

    @Test func pointNorthOfEastboundEquatorialRouteIsSigned() {
        // North of an eastbound equatorial route is "left" of course by the
        // right-hand convention used here (positive = right of course).
        let north = Coordinate(latitude: 1, longitude: 5)
        let south = Coordinate(latitude: -1, longitude: 5)
        let northGeometry = GreatCircleTrack.relativeGeometry(of: north, start: start, end: end)
        let southGeometry = GreatCircleTrack.relativeGeometry(of: south, start: start, end: end)

        // The two must have opposite sign and comparable (not necessarily identical,
        // due to sphere curvature) magnitude — this is the "signed so left/right of
        // course is distinguishable" requirement from §2.1.
        #expect(northGeometry.crossTrackError * southGeometry.crossTrackError < 0)
        #expect(abs(abs(northGeometry.crossTrackError) - abs(southGeometry.crossTrackError)) < 1000)
    }

    @Test func alongTrackFlownIsMonotonicAlongTheRoute() {
        let quarter = Coordinate(latitude: 0, longitude: 2.5)
        let half = Coordinate(latitude: 0, longitude: 5)
        let threeQuarter = Coordinate(latitude: 0, longitude: 7.5)

        let g1 = GreatCircleTrack.relativeGeometry(of: quarter, start: start, end: end)
        let g2 = GreatCircleTrack.relativeGeometry(of: half, start: start, end: end)
        let g3 = GreatCircleTrack.relativeGeometry(of: threeQuarter, start: start, end: end)

        #expect(g1.alongTrackFromStart < g2.alongTrackFromStart)
        #expect(g2.alongTrackFromStart < g3.alongTrackFromStart)
    }

    @Test func pointBehindStartHasNegativeAlongTrack() {
        let behind = Coordinate(latitude: 0, longitude: -2)
        let geometry = GreatCircleTrack.relativeGeometry(of: behind, start: start, end: end)
        #expect(geometry.alongTrackFromStart < 0)
    }
}

struct FlightPlanTests {
    @Test func denverToLosAngelesProgressIsMonotonicAndBounded() throws {
        let den = Coordinate(latitude: 39.8617, longitude: -104.6731)
        let lax = Coordinate(latitude: 33.9416, longitude: -118.4085)
        let departure = Date(timeIntervalSince1970: 1_755_639_600)
        let plan = try FlightPlan(
            flightNumber: "UA1234",
            origin: den,
            destination: lax,
            scheduledDeparture: departure,
            scheduledArrival: departure.addingTimeInterval(8400),
            aircraftICAOType: "B738",
            aircraftRegistration: nil
        )

        let atOrigin = plan.routeRelative(at: den)
        #expect(abs(atOrigin.fractionalProgress) < 0.01)

        let atDestination = plan.routeRelative(at: lax)
        #expect(abs(atDestination.fractionalProgress - 1.0) < 0.01)
        #expect(atDestination.alongTrackRemaining < 1000) // within 1 km of arrival

        // A point roughly along the route (over Nevada) should read as partial
        // progress, strictly between origin and destination.
        let overNevada = Coordinate(latitude: 36.5, longitude: -114.5)
        let midFlight = plan.routeRelative(at: overNevada)
        #expect(midFlight.fractionalProgress > 0.1)
        #expect(midFlight.fractionalProgress < 0.9)
    }

    @Test func scheduledBlockTimeIsArrivalMinusDeparture() throws {
        let departure = Date(timeIntervalSince1970: 1_755_639_600)
        let arrival = departure.addingTimeInterval(8400)
        let plan = try FlightPlan(
            flightNumber: "UA1234",
            origin: Coordinate(latitude: 0, longitude: 0),
            destination: Coordinate(latitude: 1, longitude: 1),
            scheduledDeparture: departure,
            scheduledArrival: arrival,
            aircraftICAOType: nil,
            aircraftRegistration: nil
        )
        #expect(plan.scheduledBlockTime == 8400)
    }
}
