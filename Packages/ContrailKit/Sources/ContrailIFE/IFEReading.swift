import Foundation
import ContrailCore

/// One parsed reading from an in-flight-entertainment moving-map endpoint. Plain
/// optionals, not `Channel`s -- this is the parser's raw output, before the caller
/// decides which fields to promote into `EstimatorOutput` (see `asOutsideAirData()`).
public struct IFEReading: Sendable, Equatable {
    public var staticAirTemperatureC: Double?
    public var trueAirspeedMS: Double?
    public var windSpeedMS: Double?
    public var windDirectionDeg: Double?
    // ROADMAP 3b: "payload commonly includes... ground speed, position, and time to
    // destination" too -- kept here as informational cross-checks against the
    // GNSS-derived channels `EstimatorOutput` already has, but deliberately never
    // duplicated into the schema itself (see `OutsideAirData`'s own doc comment).
    public var groundspeedMS: Double?
    public var latitude: Double?
    public var longitude: Double?
    public var timeToDestinationSeconds: Double?

    public init(
        staticAirTemperatureC: Double? = nil,
        trueAirspeedMS: Double? = nil,
        windSpeedMS: Double? = nil,
        windDirectionDeg: Double? = nil,
        groundspeedMS: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        timeToDestinationSeconds: Double? = nil
    ) {
        self.staticAirTemperatureC = staticAirTemperatureC
        self.trueAirspeedMS = trueAirspeedMS
        self.windSpeedMS = windSpeedMS
        self.windDirectionDeg = windDirectionDeg
        self.groundspeedMS = groundspeedMS
        self.latitude = latitude
        self.longitude = longitude
        self.timeToDestinationSeconds = timeToDestinationSeconds
    }

    public var isEmpty: Bool {
        staticAirTemperatureC == nil && trueAirspeedMS == nil && windSpeedMS == nil
            && windDirectionDeg == nil && groundspeedMS == nil && latitude == nil
            && longitude == nil && timeToDestinationSeconds == nil
    }

    /// Only the fields nothing else in `EstimatorOutput` can produce become
    /// `.ife`-sourced channels -- groundspeed/position/ETA stay informational-only,
    /// per `OutsideAirData`'s own doc comment.
    public func asOutsideAirData() -> OutsideAirData {
        OutsideAirData(
            staticAirTemperature: Self.channel(staticAirTemperatureC),
            trueAirspeed: Self.channel(trueAirspeedMS),
            windSpeed: Self.channel(windSpeedMS),
            windDirection: Self.channel(windDirectionDeg)
        )
    }

    private static func channel(_ value: Double?) -> Channel<Double> {
        value.map { Channel(value: $0, source: .ife) } ?? .unavailable
    }
}
