import ContrailCore

/// §5.3: a named point along a route — either a plain reporting fix (FAA NASR
/// `FIX_BASE`) or a radio navaid (`NAV_BASE`). Unified into one record type because
/// both are "a named point you can be along-track relative to," which is all §5.3's
/// on-route display needs; `navaidType`/`frequency` stay optional because a plain
/// fix has neither.
public struct NavFixRecord: Sendable, Equatable {
    public enum Kind: UInt8, Sendable, Equatable {
        case fix = 0
        case navaid = 1
    }

    public let id: String // FIX_ID or NAV_ID
    public let kind: Kind
    /// NASR's `NAV_TYPE` (e.g. "VOR", "VORTAC", "NDB") — `nil` for plain fixes.
    public let navaidType: String?
    /// NASR gives navaids a real name ("KENIE"); fixes are only ever known by
    /// their five-letter identifier, so this is `nil` for `.fix`.
    public let name: String?
    public let coordinate: Coordinate
    /// The ARTCC whose airspace this point falls under at high/low altitude —
    /// carried straight from NASR rather than recomputed from the boundary polygons,
    /// since the source data already states it authoritatively per point.
    public let artccHigh: String?
    public let artccLow: String?
    /// NASR's raw `FREQ` value — VOR-family navaids publish this in MHz, NDBs in
    /// kHz; the unit is `navaidType`-dependent, not uniform, so this is deliberately
    /// *not* named `frequencyMHz`. `nil` for plain fixes and navaid types NASR
    /// doesn't publish a frequency for.
    public let frequency: Double?

    public init(
        id: String, kind: Kind, navaidType: String?, name: String?, coordinate: Coordinate,
        artccHigh: String?, artccLow: String?, frequency: Double?
    ) {
        self.id = id; self.kind = kind; self.navaidType = navaidType; self.name = name
        self.coordinate = coordinate; self.artccHigh = artccHigh; self.artccLow = artccLow
        self.frequency = frequency
    }
}

extension NavFixRecord {
    func write(to writer: inout BinaryDatasetWriter) {
        writer.writeString(id)
        writer.writeUInt8(kind.rawValue)
        writer.writeString(navaidType ?? "")
        writer.writeString(name ?? "")
        writer.writeDouble(coordinate.latitude)
        writer.writeDouble(coordinate.longitude)
        writer.writeString(artccHigh ?? "")
        writer.writeString(artccLow ?? "")
        writer.writeDouble(frequency ?? -1)
    }

    static func read(from reader: inout BinaryDatasetReader) throws -> NavFixRecord {
        let id = try reader.readString()
        let kindRaw = try reader.readUInt8()
        let navaidType = try reader.readString()
        let name = try reader.readString()
        let latitude = try reader.readDouble()
        let longitude = try reader.readDouble()
        let artccHigh = try reader.readString()
        let artccLow = try reader.readString()
        let frequency = try reader.readDouble()
        return NavFixRecord(
            id: id, kind: NavFixRecord.Kind(rawValue: kindRaw) ?? .fix,
            navaidType: navaidType.isEmpty ? nil : navaidType,
            name: name.isEmpty ? nil : name,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            artccHigh: artccHigh.isEmpty ? nil : artccHigh,
            artccLow: artccLow.isEmpty ? nil : artccLow,
            frequency: frequency < 0 ? nil : frequency
        )
    }
}
