import Foundation

/// Where a channel's value came from — the §9 requirement that must exist from day
/// one, because Phase 3 introduces channels arriving from non-device sources (outside
/// air temperature, wind vector) and retrofitting this field would touch every log
/// ever written.
public enum ChannelSource: String, Sendable, Codable, CaseIterable {
    /// Direct device measurement.
    case gnss, barometer, imu

    /// Computed from one or more device channels (e.g. groundspeed from successive
    /// GNSS fixes via geodesic inverse — never CoreLocation's own filtered value).
    case derived

    /// §2.3 position-estimate provenance.
    case deadReckoned, fused

    /// Resolved at the gate, before departure.
    case flightPlan

    /// Reserved for 1.6 — NOAA GTG forecast comparison.
    case forecast

    /// Reserved for Phase 3 — in-flight entertainment endpoint / external sensor.
    case ife, external

    /// Not produced by this build. The whole point of this enum: `.unavailable` is
    /// how the UI tells "zero" from "unknown" (ROADMAP §3).
    case unavailable
}

/// Every measured or derived quantity in `EstimatorOutput` is wrapped in a `Channel`,
/// never a bare value. `value == nil` always means unknown — never a sentinel, never
/// zero — and `source` says why: either where the number came from, or
/// `.unavailable` if this build doesn't produce it yet (a deferred 1.x feature).
///
/// A deferred channel reports `.unavailable` and has **no UI surface** until the
/// feature that produces it ships. That is honest absence, not a stub, and it is why
/// the log schema never needs to migrate when 1.1–1.6 land.
public struct Channel<Value: Sendable & Codable & Equatable>: Sendable, Equatable {
    public let value: Value?
    public let source: ChannelSource
    /// Seconds since the underlying observation was made, at the time this
    /// `EstimatorOutput` was produced. `nil` when `value` is `nil`.
    public let age: TimeInterval?

    public init(value: Value?, source: ChannelSource, age: TimeInterval? = nil) {
        precondition(
            (value == nil) == (age == nil) || value == nil,
            "age should only be set when value is present"
        )
        self.value = value
        self.source = source
        self.age = age
    }

    /// A channel with no producer in this build. Deferred features (1.1–1.6) fill
    /// their `EstimatorOutput` fields with this constant.
    public static var unavailable: Channel<Value> {
        Channel(value: nil, source: .unavailable, age: nil)
    }
}

extension Channel: Codable {
    private enum CodingKeys: String, CodingKey {
        case value, source, age
    }

    /// Swift's auto-synthesized `Encodable` uses `encodeIfPresent` for `Optional`
    /// stored properties, which **omits the key entirely** when the value is `nil`
    /// rather than writing JSON `null`. That silently contradicts the NDJSON log
    /// schema, which relies on `value` always being present — either a number or an
    /// explicit `null` — so every consumer can do one presence check instead of
    /// distinguishing "key missing" from "key null". This conformance is written by
    /// hand specifically to guarantee that.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let value {
            try container.encode(value, forKey: .value)
        } else {
            try container.encodeNil(forKey: .value)
        }
        try container.encode(source, forKey: .source)
        if let age {
            try container.encode(age, forKey: .age)
        } else {
            try container.encodeNil(forKey: .age)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(Value.self, forKey: .value)
        source = try container.decode(ChannelSource.self, forKey: .source)
        age = try container.decodeIfPresent(TimeInterval.self, forKey: .age)
    }
}
