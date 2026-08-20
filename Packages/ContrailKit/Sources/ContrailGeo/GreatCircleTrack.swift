import Foundation
import ContrailCore

/// Cross-track and along-track geometry relative to a great-circle path, using the
/// standard spherical formulas (the "Aviation Formulary" construction, after Ed
/// Williams) with the WGS-84 mean radius. This is the §2.1 floor — "proper spherical…
/// formulas" — deliberately kept spherical rather than a full ellipsoidal geodesic
/// projection: an ellipsoidal closest-point-on-geodesic solve is materially harder and
/// its correction is far smaller than GPS position uncertainty at flight distances.
/// Point-to-point *distance* and *bearing* (motion, ETA) use `VincentyGeodesic`
/// throughout; only this track-relative geometry is spherical.
enum SphericalTrig {
    /// Haversine angular distance between two points, radians.
    static func angularDistance(_ p1: Coordinate, _ p2: Coordinate) -> Double {
        let φ1 = p1.latitude.degreesToRadians, φ2 = p2.latitude.degreesToRadians
        let Δφ = φ2 - φ1
        let Δλ = (p2.longitude - p1.longitude).degreesToRadians
        let sinΔφ2 = sin(Δφ / 2), sinΔλ2 = sin(Δλ / 2)
        let h = sinΔφ2 * sinΔφ2 + cos(φ1) * cos(φ2) * sinΔλ2 * sinΔλ2
        return 2 * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from p1 to p2, radians, normalized to [0, 2π).
    static func initialBearing(_ p1: Coordinate, _ p2: Coordinate) -> Double {
        let φ1 = p1.latitude.degreesToRadians, φ2 = p2.latitude.degreesToRadians
        let Δλ = (p2.longitude - p1.longitude).degreesToRadians
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x)
        return θ < 0 ? θ + 2 * .pi : θ
    }

    /// Smallest signed angular difference `a - b`, radians, in (-π, π].
    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        atan2(sin(a - b), cos(a - b))
    }
}

/// Cross-track and along-track distances of `point` relative to the great-circle path
/// from `start` to `end`.
public struct TrackRelativeGeometry: Sendable, Equatable {
    /// Metres. Signed: **positive means right of course**, negative means left —
    /// distinguishable, as §2.1 requires.
    public let crossTrackError: Double
    /// Metres, from `start` to the point on the great circle closest to `point`
    /// (the "foot of perpendicular"). Not clamped to the `start`–`end` segment — a
    /// point beyond `end` yields a value greater than the total route length.
    public let alongTrackFromStart: Double
}

public enum GreatCircleTrack {
    /// Computes `point`'s position relative to the great-circle path from `start` to
    /// `end`, using the Aviation Formulary cross-track/along-track construction.
    public static func relativeGeometry(
        of point: Coordinate,
        start: Coordinate,
        end: Coordinate
    ) -> TrackRelativeGeometry {
        let R = WGS84.meanRadius

        let δ13 = SphericalTrig.angularDistance(start, point)
        let θ13 = SphericalTrig.initialBearing(start, point)
        let θ12 = SphericalTrig.initialBearing(start, end)

        let dxt = asin(
            (sin(δ13) * sin(SphericalTrig.angleDifference(θ13, θ12))).clampedToUnitInterval()
        ) * R

        // acos argument can drift fractionally outside [-1, 1] from floating-point
        // error when the point lies almost exactly on the great circle.
        let ratio = (cos(δ13) / cos(dxt / R)).clampedToUnitInterval()
        let dat = acos(ratio) * R

        // Along-track sign: if the point is "behind" start (bearing to it points
        // away from end), the foot of perpendicular is behind start too.
        let bearingDelta = abs(SphericalTrig.angleDifference(θ13, θ12))
        let signedAlongTrack = bearingDelta > .pi / 2 ? -dat : dat

        return TrackRelativeGeometry(crossTrackError: dxt, alongTrackFromStart: signedAlongTrack)
    }
}

private extension Double {
    /// Clamps to [-1, 1] — guards `asin`/`acos` against NaN from float error at the
    /// domain boundary.
    func clampedToUnitInterval() -> Double {
        Swift.min(1, Swift.max(-1, self))
    }
}
