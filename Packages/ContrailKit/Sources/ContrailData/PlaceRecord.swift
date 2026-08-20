import ContrailCore

/// §5.6: a populated place from GeoNames `cities1000` (population >= 1000 — deliberately
/// not `cities5000`, whose cutoff excludes places like Ely, Nevada that §5.6 itself
/// names as the reason "nearest city" must never lie over empty country).
public struct PlaceRecord: Sendable, Equatable {
    public let name: String
    public let coordinate: Coordinate
    public let countryCode: String   // ISO 3166-1 alpha-2
    public let admin1Code: String    // GeoNames admin1 code, e.g. "NV" for Nevada (US); may be empty
    public let population: UInt32

    public init(name: String, coordinate: Coordinate, countryCode: String, admin1Code: String, population: UInt32) {
        self.name = name; self.coordinate = coordinate
        self.countryCode = countryCode; self.admin1Code = admin1Code; self.population = population
    }

    /// §5.6's own worked example: "42 mi N of Ely, Nevada" — a full state name, not
    /// GeoNames' raw admin1 code, for the common (US) case.
    public var displayName: String {
        if countryCode == "US", let stateName = USStateNames.name(forAbbreviation: admin1Code) {
            return "\(name), \(stateName)"
        }
        return "\(name), \(countryCode)"
    }
}

extension PlaceRecord {
    func write(to writer: inout BinaryDatasetWriter) {
        writer.writeDouble(coordinate.latitude)
        writer.writeDouble(coordinate.longitude)
        writer.writeString(name)
        writer.writeString(countryCode)
        writer.writeString(admin1Code)
        writer.writeUInt32(population)
    }

    static func read(from reader: inout BinaryDatasetReader) throws -> PlaceRecord {
        let latitude = try reader.readDouble()
        let longitude = try reader.readDouble()
        let name = try reader.readString()
        let countryCode = try reader.readString()
        let admin1Code = try reader.readString()
        let population = try reader.readUInt32()
        return PlaceRecord(
            name: name, coordinate: Coordinate(latitude: latitude, longitude: longitude),
            countryCode: countryCode, admin1Code: admin1Code, population: population
        )
    }
}
