import Foundation

/// ROADMAP Phase 2 -- Identity: "Generated profile section -- what your flight
/// history says about you... derived, not self-reported, which is what makes it
/// interesting." Every field here is produced by `GeneratedProfileCompiler` from
/// real logged flights; nothing in this type is ever written by the user directly.
public struct GeneratedProfileStats: Sendable, Equatable {
    public struct RouteFrequency: Sendable, Equatable, Identifiable {
        public var id: String { route }
        /// `"ICAO-ICAO"`, e.g. `"KDEN-KLAX"`.
        public let route: String
        public let count: Int
        /// The average of each flight's own mean EDR^(1/3) on this route -- averaging
        /// per flight first, not pooling every sample, so a longer flight doesn't
        /// out-vote a shorter one just by having more samples.
        public let averageEDRCubeRoot: Double?

        public init(route: String, count: Int, averageEDRCubeRoot: Double?) {
            self.route = route
            self.count = count
            self.averageEDRCubeRoot = averageEDRCubeRoot
        }
    }

    public let flightsLogged: Int
    /// Sum, across all flights, of the elapsed time between the first and last
    /// non-taxi sample -- an approximation of time airborne, not a precise
    /// climb/cruise/descent integral.
    public let hoursAtAltitude: Double
    public let totalDistanceNauticalMiles: Double
    public let routes: [RouteFrequency]
    public let roughestRoute: RouteFrequency?
    public let smoothestRoute: RouteFrequency?
    /// The pilot's own mean EDR^(1/3) across every flight with turbulence data --
    /// the baseline `turbulenceLuckDelta` is measured against.
    public let personalAverageEDRCubeRoot: Double?
    /// Mean (measured − forecast) EDR^(1/3) across every sample where both are
    /// present, drawn from the exact residual §4.3 already computes per sample.
    /// Positive means flights consistently ran rougher than GTG predicted
    /// ("cursed"); negative means smoother ("lucky"). `nil` until at least one
    /// flight has both a measurement and a forecast fetched.
    public let turbulenceLuckDelta: Double?
    /// Mean of each flight's final logged `scheduleDelta` -- the closest available
    /// proxy for actual arrival delay, since 1.0 never records a separate "wheels
    /// down" event. Negative means early on average.
    public let averageScheduleDeltaSeconds: Double?

    public init(
        flightsLogged: Int,
        hoursAtAltitude: Double,
        totalDistanceNauticalMiles: Double,
        routes: [RouteFrequency],
        roughestRoute: RouteFrequency?,
        smoothestRoute: RouteFrequency?,
        personalAverageEDRCubeRoot: Double?,
        turbulenceLuckDelta: Double?,
        averageScheduleDeltaSeconds: Double?
    ) {
        self.flightsLogged = flightsLogged
        self.hoursAtAltitude = hoursAtAltitude
        self.totalDistanceNauticalMiles = totalDistanceNauticalMiles
        self.routes = routes
        self.roughestRoute = roughestRoute
        self.smoothestRoute = smoothestRoute
        self.personalAverageEDRCubeRoot = personalAverageEDRCubeRoot
        self.turbulenceLuckDelta = turbulenceLuckDelta
        self.averageScheduleDeltaSeconds = averageScheduleDeltaSeconds
    }

    public static let empty = GeneratedProfileStats(
        flightsLogged: 0,
        hoursAtAltitude: 0,
        totalDistanceNauticalMiles: 0,
        routes: [],
        roughestRoute: nil,
        smoothestRoute: nil,
        personalAverageEDRCubeRoot: nil,
        turbulenceLuckDelta: nil,
        averageScheduleDeltaSeconds: nil
    )
}
