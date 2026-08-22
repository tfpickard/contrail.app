import Foundation

/// A strategy for turning one vendor's response body into an `IFEReading`. Plural,
/// pluggable parsers exist because ROADMAP 3b is explicit that "the shape differs by
/// vendor" -- `IFEProber` tries each parser against a target's response until one
/// returns a non-nil reading.
public protocol IFEPayloadParser: Sendable {
    func parse(_ data: Data) -> IFEReading?
}

/// The default parser: recursively walks whatever JSON tree comes back and matches
/// keys against a set of known aliases, case-insensitively, regardless of nesting
/// depth. Deliberately not shape-specific -- with no confirmed schema for any real
/// endpoint (see `IFEProbeTarget.knownTargets`'s own caveat), a defensive sniff that
/// finds a recognizable key *anywhere* in the tree is more robust than a parser
/// written against one assumed shape that breaks the moment a real payload nests
/// differently.
public struct GenericKeySniffingParser: IFEPayloadParser {
    public init() {}

    private static let temperatureKeys = [
        "sat", "staticairtemp", "statictemp", "oat", "outsideairtemp", "temperature", "temp",
    ]
    private static let airspeedKeys = ["tas", "trueairspeed", "airspeed"]
    private static let windSpeedKeys = ["windspeed", "wind_speed", "windvelocity"]
    private static let windDirectionKeys = ["winddirection", "wind_direction", "wind_dir", "winddir"]
    private static let groundspeedKeys = ["groundspeed", "ground_speed", "gs"]
    private static let latitudeKeys = ["lat", "latitude"]
    private static let longitudeKeys = ["lon", "lng", "longitude"]
    private static let timeToDestinationKeys = ["timetodestination", "time_to_destination", "ttd", "eta_seconds"]

    public func parse(_ data: Data) -> IFEReading? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let flattened = Self.flatten(json)
        guard !flattened.isEmpty else { return nil }

        let reading = IFEReading(
            staticAirTemperatureC: Self.firstDouble(flattened, keys: Self.temperatureKeys),
            trueAirspeedMS: Self.firstDouble(flattened, keys: Self.airspeedKeys),
            windSpeedMS: Self.firstDouble(flattened, keys: Self.windSpeedKeys),
            windDirectionDeg: Self.firstDouble(flattened, keys: Self.windDirectionKeys),
            groundspeedMS: Self.firstDouble(flattened, keys: Self.groundspeedKeys),
            latitude: Self.firstDouble(flattened, keys: Self.latitudeKeys),
            longitude: Self.firstDouble(flattened, keys: Self.longitudeKeys),
            timeToDestinationSeconds: Self.firstDouble(flattened, keys: Self.timeToDestinationKeys)
        )
        return reading.isEmpty ? nil : reading
    }

    private static func flatten(_ json: Any) -> [String: Double] {
        var result: [String: Double] = [:]
        flatten(json, into: &result)
        return result
    }

    private static func flatten(_ json: Any, into result: inout [String: Double]) {
        if let dict = json as? [String: Any] {
            for (key, value) in dict {
                if let number = numericValue(value) {
                    // First match wins -- an endpoint that reports the same field
                    // under two aliases is vanishingly unlikely, and this keeps the
                    // walk order (dictionary iteration) irrelevant to correctness
                    // for any real single-shape payload.
                    if result[key.lowercased()] == nil {
                        result[key.lowercased()] = number
                    }
                } else {
                    flatten(value, into: &result)
                }
            }
        } else if let array = json as? [Any] {
            for element in array { flatten(element, into: &result) }
        }
    }

    private static func numericValue(_ value: Any) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func firstDouble(_ flattened: [String: Double], keys: [String]) -> Double? {
        for key in keys where flattened[key] != nil {
            return flattened[key]
        }
        return nil
    }
}
