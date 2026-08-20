import Foundation
import ContrailCore

/// Errors from the iterative geodesic solvers. Both are extremely unlikely at flight
/// distances — non-convergence only arises near antipodal points, and no scheduled
/// commercial flight is antipodal.
public enum GeodesicError: Error, Sendable {
    case didNotConverge
}

/// The result of solving the geodesic inverse problem: the distance and bearings
/// between two points on the WGS-84 ellipsoid.
public struct GeodesicInverseResult: Sendable, Equatable {
    /// Metres, along the ellipsoid surface.
    public let distance: Double
    /// Degrees true, at the start point, in the direction of `to`.
    public let initialBearing: Double
    /// Degrees true, at the end point, **continuing in the same direction of
    /// travel** — i.e. the bearing you'd be on if you flew straight through the end
    /// point. This is the opposite of the "back azimuth" some geodesy references
    /// (including Vincenty's original 1975 paper) report as α2; the two are always
    /// 180° apart. Forward-continuing is used here because `MotionEstimate.trueCourse`
    /// reuses this routine between successive fixes, where "the direction of travel"
    /// is the only sensible meaning for a bearing at a point.
    public let finalBearing: Double
}

/// The result of solving the geodesic direct problem: the destination point and
/// reverse bearing given a start point, initial bearing, and distance.
public struct GeodesicDirectResult: Sendable, Equatable {
    public let destination: Coordinate
    /// Degrees true, at the destination, pointing back toward the start.
    public let finalBearing: Double
}

/// Vincenty's formulae (1975) for the direct and inverse geodesic problems on the
/// WGS-84 ellipsoid. Reference implementation validated against the paper's own
/// published test case in `VincentyGeodesicTests` (Flinders Peak → Buninyong).
public enum VincentyGeodesic {
    private static let convergenceThreshold = 1e-12
    private static let maxIterations = 200

    /// Solves the inverse problem: given two points, find the distance between them
    /// and the initial/final bearings along the connecting geodesic.
    public static func inverse(from p1: Coordinate, to p2: Coordinate) throws -> GeodesicInverseResult {
        let a = WGS84.a, f = WGS84.f, b = WGS84.b

        let φ1 = p1.latitude.degreesToRadians
        let φ2 = p2.latitude.degreesToRadians
        let L = (p2.longitude - p1.longitude).degreesToRadians

        let U1 = atan((1 - f) * tan(φ1))
        let U2 = atan((1 - f) * tan(φ2))
        let sinU1 = sin(U1), cosU1 = cos(U1)
        let sinU2 = sin(U2), cosU2 = cos(U2)

        var λ = L
        var sinσ = 0.0, cosσ = 0.0, σ = 0.0, cosSqα = 0.0, cos2σm = 0.0
        var converged = false

        for _ in 0..<maxIterations {
            let sinλ = sin(λ), cosλ = cos(λ)
            let sinσTerm1 = cosU2 * sinλ
            let sinσTerm2 = cosU1 * sinU2 - sinU1 * cosU2 * cosλ
            sinσ = sqrt(sinσTerm1 * sinσTerm1 + sinσTerm2 * sinσTerm2)

            if sinσ == 0 {
                // Coincident points.
                return GeodesicInverseResult(distance: 0, initialBearing: 0, finalBearing: 0)
            }

            cosσ = sinU1 * sinU2 + cosU1 * cosU2 * cosλ
            σ = atan2(sinσ, cosσ)

            let sinα = cosU1 * cosU2 * sinλ / sinσ
            cosSqα = 1 - sinα * sinα

            cos2σm = cosSqα != 0 ? cosσ - 2 * sinU1 * sinU2 / cosSqα : 0

            let C = f / 16 * cosSqα * (4 + f * (4 - 3 * cosSqα))
            let λPrev = λ
            λ = L + (1 - C) * f * sinα
                * (σ + C * sinσ * (cos2σm + C * cosσ * (-1 + 2 * cos2σm * cos2σm)))

            if abs(λ - λPrev) < convergenceThreshold {
                converged = true
                break
            }
        }

        guard converged else { throw GeodesicError.didNotConverge }

        let uSq = cosSqα * (a * a - b * b) / (b * b)
        let A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))
        let Δσ = B * sinσ * (cos2σm + B / 4 * (cosσ * (-1 + 2 * cos2σm * cos2σm)
            - B / 6 * cos2σm * (-3 + 4 * sinσ * sinσ) * (-3 + 4 * cos2σm * cos2σm)))

        let distance = b * A * (σ - Δσ)

        let sinλ = sin(λ), cosλ = cos(λ)
        let α1 = atan2(cosU2 * sinλ, cosU1 * sinU2 - sinU1 * cosU2 * cosλ).radiansToDegrees
        let α2 = atan2(cosU1 * sinλ, -sinU1 * cosU2 + cosU1 * sinU2 * cosλ).radiansToDegrees

        return GeodesicInverseResult(
            distance: distance,
            initialBearing: α1.normalizedDegrees,
            finalBearing: α2.normalizedDegrees
        )
    }

    /// Solves the direct problem: given a start point, initial bearing, and distance,
    /// find the destination point and the reverse bearing there.
    public static func direct(
        from start: Coordinate,
        initialBearing: Double,
        distance: Double
    ) throws -> GeodesicDirectResult {
        let a = WGS84.a, f = WGS84.f, b = WGS84.b

        let φ1 = start.latitude.degreesToRadians
        let α1 = initialBearing.degreesToRadians
        let s = distance

        let U1 = atan((1 - f) * tan(φ1))
        let sinU1 = sin(U1), cosU1 = cos(U1)
        let sinα1 = sin(α1), cosα1 = cos(α1)

        let σ1 = atan2(tan(U1), cosα1)
        let sinα = cosU1 * sinα1
        let cosSqα = 1 - sinα * sinα

        let uSq = cosSqα * (a * a - b * b) / (b * b)
        let A = 1 + uSq / 16384 * (4096 + uSq * (-768 + uSq * (320 - 175 * uSq)))
        let B = uSq / 1024 * (256 + uSq * (-128 + uSq * (74 - 47 * uSq)))

        var σ = s / (b * A)
        var converged = false
        var cos2σm = 0.0, sinσ = 0.0, cosσ = 0.0

        for _ in 0..<maxIterations {
            cos2σm = cos(2 * σ1 + σ)
            sinσ = sin(σ)
            cosσ = cos(σ)
            let Δσ = B * sinσ * (cos2σm + B / 4 * (cosσ * (-1 + 2 * cos2σm * cos2σm)
                - B / 6 * cos2σm * (-3 + 4 * sinσ * sinσ) * (-3 + 4 * cos2σm * cos2σm)))
            let σPrev = σ
            σ = s / (b * A) + Δσ
            if abs(σ - σPrev) < convergenceThreshold {
                converged = true
                break
            }
        }

        guard converged else { throw GeodesicError.didNotConverge }

        let tmp = sinU1 * sinσ - cosU1 * cosσ * cosα1
        let φ2 = atan2(
            sinU1 * cosσ + cosU1 * sinσ * cosα1,
            (1 - f) * sqrt(sinα * sinα + tmp * tmp)
        )
        let λ = atan2(
            sinσ * sinα1,
            cosU1 * cosσ - sinU1 * sinσ * cosα1
        )
        let C = f / 16 * cosSqα * (4 + f * (4 - 3 * cosSqα))
        let L = λ - (1 - C) * f * sinα
            * (σ + C * sinσ * (cos2σm + C * cosσ * (-1 + 2 * cos2σm * cos2σm)))

        let λ2 = L + start.longitude.degreesToRadians
        let α2 = atan2(sinα, -tmp).radiansToDegrees

        return GeodesicDirectResult(
            destination: Coordinate(
                latitude: φ2.radiansToDegrees,
                longitude: λ2.radiansToDegrees
            ),
            finalBearing: α2.normalizedDegrees
        )
    }
}
