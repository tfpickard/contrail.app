import Foundation

/// GTG's published levels are round flight levels (1,000 ft increments -- GribStream's
/// own documented example, `"10058 m above mean sea level"`, is exactly FL330
/// converted to metres: `33,000 ft × 0.3048 = 10,058.4 m`, rounding to a clean metre
/// figure only because the *underlying* level is a round number of feet, not metres).
/// Generating level strings from feet first, then converting, is what makes the
/// request match the API's real grid instead of a metres-rounded guess that happens
/// to miss it.
public enum GTGLevel {
    /// Every published flight level from `FL010` up to (and including) the one at or
    /// above `topMetres`, so a route's cruise altitude is always bracketed for the
    /// altitude interpolation §4.2 requires ("not optional").
    public static func flightLevelsMetres(upTo topMetres: Double) -> [Double] {
        let topFeet = topMetres / 0.3048
        var feet = 1_000.0
        var levels: [Double] = []
        while true {
            levels.append(feet * 0.3048)
            if feet >= topFeet { break }
            feet += 1_000
        }
        return levels
    }

    /// GribStream's documented level-string format: `"<metres> m above mean sea level"`,
    /// where `<metres>` is the *rounded* metre equivalent of the underlying round
    /// flight level in feet.
    public static func levelString(forAltitudeMetres metres: Double) -> String {
        "\(Int(metres.rounded())) m above mean sea level"
    }

    /// The two published levels bracketing `altitudeMetres`, for altitude
    /// interpolation. Returns a single repeated level at the very bottom/top of the
    /// generated range rather than extrapolating past what was fetched.
    public static func bracketingLevels(_ levels: [Double], around altitudeMetres: Double) -> (Double, Double) {
        let sorted = levels.sorted()
        guard let first = sorted.first, let last = sorted.last else { return (0, 0) }
        if altitudeMetres <= first { return (first, first) }
        if altitudeMetres >= last { return (last, last) }
        var lower = first
        for level in sorted {
            if level > altitudeMetres { return (lower, level) }
            lower = level
        }
        return (last, last)
    }
}
