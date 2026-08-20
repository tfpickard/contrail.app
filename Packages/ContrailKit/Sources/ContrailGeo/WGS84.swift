import Foundation

/// WGS-84 reference ellipsoid constants, used throughout for geodesic (not spherical)
/// point-to-point distance and bearing — the §2.1 requirement that "great circle math
/// must be correct at flight distances," using "proper spherical (or better, WGS-84
/// ellipsoidal) formulas."
public enum WGS84 {
    /// Semi-major axis, metres.
    public static let a = 6_378_137.0
    /// Flattening.
    public static let f = 1.0 / 298.257223563
    /// Semi-minor axis, metres.
    public static let b = a * (1 - f)

    /// Mean (authalic) Earth radius, metres — used only where a spherical
    /// approximation is the deliberate choice (see `GreatCircleTrack`), never for
    /// point-to-point distance or bearing.
    public static let meanRadius = 6_371_008.8
}

extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }

    /// Normalizes an angle in degrees to `[0, 360)`.
    var normalizedDegrees: Double {
        let r = self.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
