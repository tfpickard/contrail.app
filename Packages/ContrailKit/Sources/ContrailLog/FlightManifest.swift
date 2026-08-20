import Foundation
import ContrailCore

/// §6: "a manifest per flight capturing everything fetched pre-flight... a log must
/// be fully self-describing years later with no network." Kept independent of
/// `FlightPlan` deliberately — `FlightPlan` (ContrailGeo) is the minimal
/// route-geometry contract `Estimator` needs; a manifest additionally wants airport
/// codes, elevation, and timezone that only the pre-flight resolution flow (§5, not
/// yet built) will have. Constructing one is the resolution flow's job, once it
/// exists; this type just defines the faithful, versioned shape.
public struct FlightManifest: Sendable, Equatable {
    public struct AppInfo: Sendable, Codable, Equatable {
        public let version: String
        public let build: String
        public let phase: String
        public init(version: String, build: String, phase: String) {
            self.version = version; self.build = build; self.phase = phase
        }
    }

    public struct DeviceInfo: Sendable, Codable, Equatable {
        public let model: String
        public let os: String
        public init(model: String, os: String) { self.model = model; self.os = os }
    }

    public struct ResolutionInfo: Sendable, Codable, Equatable {
        public let provider: String   // "manual" | "aeroapi" | ...
        public let resolvedAt: Date
        public init(provider: String, resolvedAt: Date) { self.provider = provider; self.resolvedAt = resolvedAt }
    }

    public struct AirportInfo: Sendable, Codable, Equatable {
        public let icao: String
        public let iata: String?
        public let coordinate: Coordinate
        public let elevation: Double?     // metres
        public let timezone: String?      // IANA identifier
        public init(icao: String, iata: String?, coordinate: Coordinate, elevation: Double?, timezone: String?) {
            self.icao = icao; self.iata = iata; self.coordinate = coordinate
            self.elevation = elevation; self.timezone = timezone
        }
    }

    public struct ScheduledTimes: Sendable, Codable, Equatable {
        public let departure: Date
        public let arrival: Date
        public let blockTime: TimeInterval
        public init(departure: Date, arrival: Date, blockTime: TimeInterval) {
            self.departure = departure; self.arrival = arrival; self.blockTime = blockTime
        }
    }

    public struct AircraftInfo: Sendable, Codable, Equatable {
        public let icaoType: String?
        public let registration: String?
        public init(icaoType: String?, registration: String?) {
            self.icaoType = icaoType; self.registration = registration
        }
    }

    public struct FlightInfo: Sendable, Equatable {
        public let number: String
        public let date: String            // "YYYY-MM-DD", local to origin
        public let origin: AirportInfo
        public let destination: AirportInfo
        public let scheduled: ScheduledTimes
        public let aircraft: AircraftInfo
        /// §5.3: the filed route waypoint string, when available. Always `nil` in
        /// 1.0 — the field exists so 1.4 (route intelligence) never migrates a log.
        public let filedRoute: [String]?
        public init(
            number: String, date: String, origin: AirportInfo, destination: AirportInfo,
            scheduled: ScheduledTimes, aircraft: AircraftInfo, filedRoute: [String]?
        ) {
            self.number = number; self.date = date; self.origin = origin; self.destination = destination
            self.scheduled = scheduled; self.aircraft = aircraft; self.filedRoute = filedRoute
        }
    }

    public struct AssetInfo: Sendable, Codable, Equatable {
        public let kind: String
        public let id: String
        public let bytes: Int
        public let sha256: String
        public let verified: Bool
        public init(kind: String, id: String, bytes: Int, sha256: String, verified: Bool) {
            self.kind = kind; self.id = id; self.bytes = bytes; self.sha256 = sha256; self.verified = verified
        }
    }

    public let schema: SchemaVersion
    public let flightID: String
    public let app: AppInfo
    public let device: DeviceInfo
    public let resolution: ResolutionInfo
    public let flight: FlightInfo
    /// Pre-flight-verified bundled/downloaded assets (§5). Empty in 1.0 until
    /// `ContrailData` and the corridor map (1.3) exist to populate it.
    public let assets: [AssetInfo]
    /// §4.2/1.6: the GTG forecast grid slice, when one was fetched. Always `nil` in
    /// 1.0 — present from day one so 1.6 never migrates a log.
    public let forecast: String?
    public let sensorSource: String   // "live" | "replay"

    public init(
        schema: SchemaVersion = .current,
        flightID: String,
        app: AppInfo,
        device: DeviceInfo,
        resolution: ResolutionInfo,
        flight: FlightInfo,
        assets: [AssetInfo] = [],
        forecast: String? = nil,
        sensorSource: String
    ) {
        self.schema = schema
        self.flightID = flightID
        self.app = app
        self.device = device
        self.resolution = resolution
        self.flight = flight
        self.assets = assets
        self.forecast = forecast
        self.sensorSource = sensorSource
    }
}

// MARK: - Explicit-null Codable for the two fields the plan requires to appear as
// literal JSON `null`, not an omitted key, so 1.4/1.6 never need to migrate an
// existing manifest (same rationale, and same Swift auto-synthesis gap, as
// `Channel`'s hand-written Codable in ContrailCore).

extension FlightManifest.FlightInfo: Codable {
    private enum CodingKeys: String, CodingKey {
        case number, date, origin, destination, scheduled, aircraft, filedRoute
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(number, forKey: .number)
        try container.encode(date, forKey: .date)
        try container.encode(origin, forKey: .origin)
        try container.encode(destination, forKey: .destination)
        try container.encode(scheduled, forKey: .scheduled)
        try container.encode(aircraft, forKey: .aircraft)
        if let filedRoute {
            try container.encode(filedRoute, forKey: .filedRoute)
        } else {
            try container.encodeNil(forKey: .filedRoute)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        number = try container.decode(String.self, forKey: .number)
        date = try container.decode(String.self, forKey: .date)
        origin = try container.decode(FlightManifest.AirportInfo.self, forKey: .origin)
        destination = try container.decode(FlightManifest.AirportInfo.self, forKey: .destination)
        scheduled = try container.decode(FlightManifest.ScheduledTimes.self, forKey: .scheduled)
        aircraft = try container.decode(FlightManifest.AircraftInfo.self, forKey: .aircraft)
        filedRoute = try container.decodeIfPresent([String].self, forKey: .filedRoute)
    }
}

extension FlightManifest: Codable {
    private enum CodingKeys: String, CodingKey {
        case schema, flightID, app, device, resolution, flight, assets, forecast, sensorSource
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(flightID, forKey: .flightID)
        try container.encode(app, forKey: .app)
        try container.encode(device, forKey: .device)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(flight, forKey: .flight)
        try container.encode(assets, forKey: .assets)
        if let forecast {
            try container.encode(forecast, forKey: .forecast)
        } else {
            try container.encodeNil(forKey: .forecast)
        }
        try container.encode(sensorSource, forKey: .sensorSource)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(SchemaVersion.self, forKey: .schema)
        flightID = try container.decode(String.self, forKey: .flightID)
        app = try container.decode(AppInfo.self, forKey: .app)
        device = try container.decode(DeviceInfo.self, forKey: .device)
        resolution = try container.decode(ResolutionInfo.self, forKey: .resolution)
        flight = try container.decode(FlightInfo.self, forKey: .flight)
        assets = try container.decode([AssetInfo].self, forKey: .assets)
        forecast = try container.decodeIfPresent(String.self, forKey: .forecast)
        sensorSource = try container.decode(String.self, forKey: .sensorSource)
    }
}
