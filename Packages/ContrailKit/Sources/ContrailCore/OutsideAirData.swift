/// ROADMAP Phase 3b -- Aircraft data endpoint: "the only source of genuine *outside*
/// atmospheric data in the app... static air temperature, true airspeed, wind
/// vector." Groundspeed, position, and ETA already exist elsewhere in
/// `EstimatorOutput` (`MotionEstimate`/`RouteRelative`) from GNSS -- this struct
/// carries only what nothing else in the schema can produce: data that requires a
/// source outside the pressurized cabin, arriving (when it arrives at all) from an
/// in-flight-entertainment moving-map endpoint via `.ife`-sourced channels.
public struct OutsideAirData: Sendable, Codable, Equatable {
    public let staticAirTemperature: Channel<Double>   // degrees Celsius
    public let trueAirspeed: Channel<Double>            // m/s
    public let windSpeed: Channel<Double>               // m/s
    public let windDirection: Channel<Double>           // degrees true, direction the wind is FROM

    public init(
        staticAirTemperature: Channel<Double>,
        trueAirspeed: Channel<Double>,
        windSpeed: Channel<Double>,
        windDirection: Channel<Double>
    ) {
        self.staticAirTemperature = staticAirTemperature
        self.trueAirspeed = trueAirspeed
        self.windSpeed = windSpeed
        self.windDirection = windDirection
    }

    /// No IFE endpoint reachable (the common case -- ROADMAP: "failure costs
    /// nothing, because the Phase 1 core stands entirely alone").
    public static let unavailable = OutsideAirData(
        staticAirTemperature: .unavailable, trueAirspeed: .unavailable,
        windSpeed: .unavailable, windDirection: .unavailable
    )
}
