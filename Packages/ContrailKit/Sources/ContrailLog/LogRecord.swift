import Foundation
import ContrailCore

/// The on-disk NDJSON record — a deliberately compact mirror of `EstimatorOutput`,
/// matching the plan's own schema exactly (short keys, since "this file is written
/// for hours"). Kept as a distinct type rather than encoding `EstimatorOutput`
/// directly: the wire format's abbreviations (`pos`, `mot`, `gs`, `xte`, ...) are a
/// storage-format decision, independent of the Swift-side contract's full names.
public struct LogRecord: Sendable, Equatable {
    public let schema: SchemaVersion
    public let kind: Kind
    public let t: Date
    public let uptime: TimeInterval
    public let position: PositionEstimate
    public let motion: MotionEstimate
    public let cabin: CabinEnvironment
    public let turbulence: TurbulenceEstimate
    public let route: RouteRelative
    public let phase: Channel<FlightPhase>

    /// `"s"` sample, `"e"` event (1.2's peak events, GPS dropout markers), `"m"` user
    /// marker. Only `.sample` is produced in 1.0; the discriminator exists from day
    /// one so `.event`/`.marker` are additive later, never a schema migration.
    public enum Kind: String, Sendable, Codable, Equatable {
        case sample = "s"
        case event = "e"
        case marker = "m"
    }

    public init(schema: SchemaVersion = .current, kind: Kind = .sample, output: EstimatorOutput) {
        self.schema = schema
        self.kind = kind
        self.t = output.t
        self.uptime = output.uptime
        self.position = output.position
        self.motion = output.motion
        self.cabin = output.cabin
        self.turbulence = output.turbulence
        self.route = output.route
        self.phase = output.phase
    }
}

// MARK: - Compact Codable

extension LogRecord: Codable {
    private enum CodingKeys: String, CodingKey {
        case schema = "v", kind = "k", t, uptime = "u"
        case position = "pos", motion = "mot", cabin = "cab", turbulence = "trb", route = "rte", phase = "ph"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([schema.major, schema.minor], forKey: .schema)
        try container.encode(kind, forKey: .kind)
        try container.encode(t.timeIntervalSince1970, forKey: .t)
        try container.encode(uptime, forKey: .uptime)
        try container.encode(PositionWire(position), forKey: .position)
        try container.encode(MotionWire(motion), forKey: .motion)
        try container.encode(CabinWire(cabin), forKey: .cabin)
        try container.encode(TurbulenceWire(turbulence), forKey: .turbulence)
        try container.encode(RouteWire(route), forKey: .route)
        try container.encode(phase, forKey: .phase)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let versionPair = try container.decode([Int].self, forKey: .schema)
        guard versionPair.count == 2 else {
            throw DecodingError.dataCorruptedError(
                forKey: .schema, in: container, debugDescription: "expected [major, minor]"
            )
        }
        schema = SchemaVersion(major: versionPair[0], minor: versionPair[1])
        kind = try container.decode(Kind.self, forKey: .kind)
        t = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .t))
        uptime = try container.decode(TimeInterval.self, forKey: .uptime)
        position = try container.decode(PositionWire.self, forKey: .position).model
        motion = try container.decode(MotionWire.self, forKey: .motion).model
        cabin = try container.decode(CabinWire.self, forKey: .cabin).model
        turbulence = try container.decode(TurbulenceWire.self, forKey: .turbulence).model
        route = try container.decode(RouteWire.self, forKey: .route).model
        phase = try container.decode(Channel<FlightPhase>.self, forKey: .phase)
    }
}

// MARK: - Wire-format structs (private, encode/decode-only adapters to short keys)

/// Encodes/decodes a `Coordinate` as a compact `[latitude, longitude]` array, per the
/// plan's schema (`"fu":[39.8617,-104.6731]`) — deliberately not `Coordinate`'s own
/// default object-style Codable, which stays as-is for its other uses (raw sensor
/// samples, general round-trips) where a self-describing object is preferable.
private struct CoordinateWire: Codable, Equatable, Sendable {
    let value: Coordinate

    init(_ value: Coordinate) { self.value = value }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let latitude = try container.decode(Double.self)
        let longitude = try container.decode(Double.self)
        value = Coordinate(latitude: latitude, longitude: longitude)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(value.latitude)
        try container.encode(value.longitude)
    }
}

private struct PositionWire: Codable {
    let fu: Channel<CoordinateWire>, cr: Channel<Double>
    let gn: Channel<CoordinateWire>, dr: Channel<CoordinateWire>
    let ha: Channel<Double>, va: Channel<Double>, tsf: Channel<Double>, alt: Channel<Double>

    init(_ m: PositionEstimate) {
        fu = Channel(value: m.fused.value.map(CoordinateWire.init), source: m.fused.source, age: m.fused.age)
        cr = m.confidenceRadius
        gn = Channel(value: m.gnss.value.map(CoordinateWire.init), source: m.gnss.source, age: m.gnss.age)
        dr = Channel(value: m.deadReckoned.value.map(CoordinateWire.init), source: m.deadReckoned.source, age: m.deadReckoned.age)
        ha = m.horizontalAccuracy; va = m.verticalAccuracy; tsf = m.timeSinceValidFix; alt = m.altitudeGPS
    }
    var model: PositionEstimate {
        PositionEstimate(
            fused: Channel(value: fu.value?.value, source: fu.source, age: fu.age),
            confidenceRadius: cr,
            gnss: Channel(value: gn.value?.value, source: gn.source, age: gn.age),
            deadReckoned: Channel(value: dr.value?.value, source: dr.source, age: dr.age),
            horizontalAccuracy: ha, verticalAccuracy: va, timeSinceValidFix: tsf, altitudeGPS: alt
        )
    }
}

private struct MotionWire: Codable {
    let gs: Channel<Double>, tc: Channel<Double>, tar: Channel<Double>
    let vs: Channel<Double>, la: Channel<Double>, cls: Channel<Double>, clc: Channel<Double>

    init(_ m: MotionEstimate) {
        gs = m.groundspeed; tc = m.trueCourse; tar = m.trackAngleRate
        vs = m.verticalSpeed; la = m.longitudinalAcceleration; cls = m.clSpeed; clc = m.clCourse
    }
    var model: MotionEstimate {
        MotionEstimate(
            groundspeed: gs, trueCourse: tc, trackAngleRate: tar,
            verticalSpeed: vs, longitudinalAcceleration: la, clSpeed: cls, clCourse: clc
        )
    }
}

private struct CabinWire: Codable {
    let p: Channel<Double>, pa: Channel<Double>, pr: Channel<Double>

    init(_ m: CabinEnvironment) { p = m.pressure; pa = m.pressureAltitude; pr = m.pressurizationRate }
    var model: CabinEnvironment { CabinEnvironment(pressure: p, pressureAltitude: pa, pressurizationRate: pr) }
}

private struct TurbulenceWire: Codable {
    let edr: Channel<Double>, fedr: Channel<Double>, gate: Channel<Bool>

    init(_ m: TurbulenceEstimate) { edr = m.edrCubeRoot; fedr = m.forecastEdrCubeRoot; gate = m.attitudeGateOpen }
    var model: TurbulenceEstimate {
        TurbulenceEstimate(edrCubeRoot: edr, forecastEdrCubeRoot: fedr, attitudeGateOpen: gate)
    }
}

private struct BearingToPlaceWire: Codable, Equatable {
    let n: String, b: Double, d: Double
    init(_ p: BearingToPlace) { n = p.name; b = p.bearing; d = p.distance }
    var model: BearingToPlace { BearingToPlace(name: n, bearing: b, distance: d) }
}

private struct ETAWire: Codable, Equatable {
    let a: Double, s: TimeInterval, sd: TimeInterval
    init(_ e: ETAEstimate) { a = e.arrival.timeIntervalSince1970; s = e.sigma; sd = e.scheduleDelta }
    var model: ETAEstimate { ETAEstimate(arrival: Date(timeIntervalSince1970: a), sigma: s, scheduleDelta: sd) }
}

private struct RouteWire: Codable {
    let atf: Channel<Double>, atr: Channel<Double>, xte: Channel<Double>, fp: Channel<Double>
    let city: Channel<BearingToPlaceWire>, eta: Channel<ETAWire>

    init(_ m: RouteRelative) {
        atf = m.alongTrackFlown; atr = m.alongTrackRemaining; xte = m.crossTrackError; fp = m.fractionalProgress
        city = Channel(value: m.nearestCity.value.map(BearingToPlaceWire.init), source: m.nearestCity.source, age: m.nearestCity.age)
        eta = Channel(value: m.eta.value.map(ETAWire.init), source: m.eta.source, age: m.eta.age)
    }
    var model: RouteRelative {
        RouteRelative(
            alongTrackFlown: atf, alongTrackRemaining: atr, crossTrackError: xte, fractionalProgress: fp,
            nearestCity: Channel(value: city.value?.model, source: city.source, age: city.age),
            eta: Channel(value: eta.value?.model, source: eta.source, age: eta.age)
        )
    }
}
