import Testing
@testable import ContrailForecast

struct GTGLevelTests {
    // GribStream's own documented example: FL330 (33,000 ft) renders as
    // "10058 m above mean sea level" -- not a metres-rounded guess, the real
    // published string for that level.
    @Test func levelStringMatchesGribStreamsOwnDocumentedExample() {
        let fl330Metres = 33_000.0 * 0.3048
        #expect(GTGLevel.levelString(forAltitudeMetres: fl330Metres) == "10058 m above mean sea level")
    }

    @Test func flightLevelsMetresGeneratesEveryThousandFeetUpToAndPastTheTop() {
        let levels = GTGLevel.flightLevelsMetres(upTo: 35_000 * 0.3048) // cruise ~FL350
        // FL010 through FL350 inclusive = 35 levels.
        #expect(levels.count == 35)
        #expect(abs(levels.first! - 1_000 * 0.3048) < 0.01)
        #expect(abs(levels.last! - 35_000 * 0.3048) < 0.01)
    }

    @Test func bracketingLevelsFindsTheRealPairAroundAnAltitude() {
        let levels = GTGLevel.flightLevelsMetres(upTo: 10_000 * 0.3048)
        let (lower, upper) = GTGLevel.bracketingLevels(levels, around: 5_500 * 0.3048)
        #expect(abs(lower - 5_000 * 0.3048) < 0.01)
        #expect(abs(upper - 6_000 * 0.3048) < 0.01)
    }

    @Test func bracketingLevelsClampsAtTheEdgesRatherThanExtrapolating() {
        let levels = GTGLevel.flightLevelsMetres(upTo: 10_000 * 0.3048)
        let (lower, upper) = GTGLevel.bracketingLevels(levels, around: -1000)
        #expect(lower == upper)
        #expect(abs(lower - 1_000 * 0.3048) < 0.01)
    }
}
