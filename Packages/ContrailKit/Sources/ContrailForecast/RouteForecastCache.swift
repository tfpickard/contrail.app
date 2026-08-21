import Foundation
import ContrailCore
import ContrailGeo

/// §4.2's trilinear requirement ("altitude interpolation is not optional"), applied
/// across the three axes `RouteForecastPlan` actually samples on: along-track
/// position, altitude, and forecast valid time -- pushback #3's own recommended
/// reframing of the raw grid's (lat, lon, level) axes into route-relative ones,
/// since every fetched sample already sits exactly on the route centerline
/// (cross-track = 0 by construction).
public struct RouteForecastCache: Sendable {
    private struct Key: Hashable {
        let waypointIndex: Int
        let levelIndex: Int
        let timeIndex: Int
    }

    private let waypointDistances: [Double] // sorted ascending, parallel to plan.waypoints
    private let sortedLevels: [Double]
    private let times: [Date]
    private let values: [Key: Double]

    public init(plan: RouteForecastPlan, samples: [ForecastSample]) {
        waypointDistances = plan.waypoints.map(\.alongTrackDistance)
        sortedLevels = plan.levelsMetres.sorted()
        times = plan.times

        var values: [Key: Double] = [:]
        for sample in samples {
            guard let waypointIndex = Self.nearestIndex(of: sample.coordinate, in: plan.waypoints),
                  let levelIndex = sortedLevels.firstIndex(where: { abs($0 - sample.altitudeMetres) < 1 }),
                  let timeIndex = times.firstIndex(where: { abs($0.timeIntervalSince(sample.validTime)) < 60 })
            else { continue }
            values[Key(waypointIndex: waypointIndex, levelIndex: levelIndex, timeIndex: timeIndex)] = sample.edrCubeRoot
        }
        self.values = values
    }

    /// `nil` whenever the query falls entirely outside what was fetched (before the
    /// first waypoint/level/time or after the last) or the specific corners needed
    /// were never returned by the API -- reported by the caller as `.unavailable`,
    /// never a stub value.
    public func value(alongTrackFlown: Double, altitudeMetres: Double, time: Date) -> Double? {
        guard let (w0, w1, wFrac) = Self.bracket(waypointDistances, alongTrackFlown),
              let (l0, l1, lFrac) = Self.bracket(sortedLevels, altitudeMetres),
              let (t0, t1, tFrac) = Self.bracketTimes(times, time)
        else { return nil }

        func corner(_ w: Int, _ l: Int, _ t: Int) -> Double? { values[Key(waypointIndex: w, levelIndex: l, timeIndex: t)] }

        // Standard trilinear reduction: interpolate over time first (4 edges -> 4
        // points), then altitude (2 -> 2), then along-track (2 -> 1).
        guard let v000 = corner(w0, l0, t0), let v001 = corner(w0, l0, t1),
              let v010 = corner(w0, l1, t0), let v011 = corner(w0, l1, t1),
              let v100 = corner(w1, l0, t0), let v101 = corner(w1, l0, t1),
              let v110 = corner(w1, l1, t0), let v111 = corner(w1, l1, t1)
        else { return nil }

        let v00 = lerp(v000, v001, tFrac)
        let v01 = lerp(v010, v011, tFrac)
        let v10 = lerp(v100, v101, tFrac)
        let v11 = lerp(v110, v111, tFrac)

        let v0 = lerp(v00, v01, lFrac)
        let v1 = lerp(v10, v11, lFrac)

        return lerp(v0, v1, wFrac)
    }

    private func lerp(_ a: Double, _ b: Double, _ fraction: Double) -> Double { a + (b - a) * fraction }

    /// The bracketing pair of indices (and fractional position between them) for
    /// `value` within an ascending `axis` -- `nil` if `value` is outside `[first, last]`.
    private static func bracket(_ axis: [Double], _ value: Double) -> (Int, Int, Double)? {
        guard let first = axis.first, let last = axis.last, value >= first, value <= last else { return nil }
        if axis.count == 1 { return (0, 0, 0) }
        for i in 0..<(axis.count - 1) where value >= axis[i] && value <= axis[i + 1] {
            let span = axis[i + 1] - axis[i]
            let fraction = span == 0 ? 0 : (value - axis[i]) / span
            // A query landing (near) exactly on a grid point collapses to a single
            // index rather than a real (i, i+1) pair -- otherwise a perfectly
            // reasonable exact-grid-point lookup would fail whenever the *other*
            // side happens not to have been fetched, even though its weight in the
            // interpolation is zero and it was never going to matter.
            let epsilon = 1e-9
            if fraction <= epsilon { return (i, i, 0) }
            if fraction >= 1 - epsilon { return (i + 1, i + 1, 0) }
            return (i, i + 1, fraction)
        }
        return nil
    }

    private static func bracketTimes(_ axis: [Date], _ value: Date) -> (Int, Int, Double)? {
        let seconds = axis.map { $0.timeIntervalSince1970 }
        guard let (i, j, fraction) = bracket(seconds, value.timeIntervalSince1970) else { return nil }
        return (i, j, fraction)
    }

    /// Nearest waypoint by planar lat/lon distance -- good enough to re-identify
    /// which requested waypoint a returned sample belongs to (waypoints are ~20 nm
    /// apart; float round-tripping through JSON never moves a coordinate anywhere
    /// close to that far), without pulling in `VincentyGeodesic` for what's really
    /// just an index-recovery lookup, not a navigation distance.
    private static func nearestIndex(of coordinate: Coordinate, in waypoints: [RouteForecastPlan.Waypoint]) -> Int? {
        waypoints.indices.min { a, b in
            Self.planarDistanceSquared(coordinate, waypoints[a].coordinate)
                < Self.planarDistanceSquared(coordinate, waypoints[b].coordinate)
        }
    }

    private static func planarDistanceSquared(_ a: Coordinate, _ b: Coordinate) -> Double {
        let dLat = a.latitude - b.latitude
        let dLon = a.longitude - b.longitude
        return dLat * dLat + dLon * dLon
    }
}
