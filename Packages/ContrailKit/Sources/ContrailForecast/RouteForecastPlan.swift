import Foundation
import ContrailCore
import ContrailGeo

/// §4.2's "server-side or pre-flight-side slice": rather than the phone parsing raw
/// GRIB2 (the spec's own words -- "a rabbit hole" -- confirmed by inspecting a real
/// NCEP DAFS GTG file during this build: Lambert Conformal projection, a bitmap, and
/// complex packing with second-order spatial differencing, not a simple grid a
/// hand-written decoder could safely take on in the time this feature has), this
/// plan describes a regular (waypoint × level × time) grid along the filed route --
/// exactly the query shape GribStream's `dafsgtg` API (a third-party mirror of the
/// same NCEP DAFS feed, already serving parsed values instead of raw GRIB2, per
/// pushback #12's original "own code or `gribstream` API" framing) expects, fetched
/// once at pre-flight time while there's still connectivity.
public struct RouteForecastPlan: Sendable {
    public struct Waypoint: Sendable, Equatable {
        public let alongTrackDistance: Double // m from origin
        public let coordinate: Coordinate
    }

    public let waypoints: [Waypoint]
    public let levelsMetres: [Double]
    public let times: [Date]

    public enum PlanError: Error {
        case invalidSpacing
    }

    /// - Parameters:
    ///   - flightPlan: the filed route this plan resamples along.
    ///   - waypointSpacingMetres: along-track resampling interval -- pushback #3's
    ///     own recommended shape ("resample route-relative"). ~20 nm by default: fine
    ///     enough that turbulence-relevant along-track variation isn't missed, coarse
    ///     enough that a transcontinental route stays a few dozen points, not
    ///     hundreds (GribStream's own pricing charges by coordinate bundles of 500).
    ///   - cruiseAltitudeMetres: used only to bound how high `GTGLevel` generates
    ///     levels up to -- the plan still brackets ground-to-cruise so climb/descent
    ///     altitudes are covered, not just the cruise flight level itself.
    ///   - times: forecast valid times to fetch -- typically departure and arrival,
    ///     bracketing the flight for the time-axis interpolation §4.3 implies
    ///     ("along the track" comparison needs a value near whenever the aircraft is
    ///     actually there, not just one snapshot).
    public init(
        flightPlan: FlightPlan, waypointSpacingMetres: Double = 37_040,
        cruiseAltitudeMetres: Double, times: [Date]
    ) throws {
        guard waypointSpacingMetres > 0 else { throw PlanError.invalidSpacing }

        var waypoints: [Waypoint] = []
        var distance = 0.0
        while distance < flightPlan.totalDistance {
            let coordinate = try flightPlan.position(atAlongTrackDistance: distance)
            waypoints.append(Waypoint(alongTrackDistance: distance, coordinate: coordinate))
            distance += waypointSpacingMetres
        }
        // Always include the destination itself, even if it doesn't land exactly on
        // a spacing multiple -- otherwise the last few percent of the route has no
        // bracketing waypoint to interpolate against.
        waypoints.append(Waypoint(
            alongTrackDistance: flightPlan.totalDistance,
            coordinate: try flightPlan.position(atAlongTrackDistance: flightPlan.totalDistance)
        ))

        self.waypoints = waypoints
        self.levelsMetres = GTGLevel.flightLevelsMetres(upTo: cruiseAltitudeMetres)
        self.times = times
    }
}
