import ContrailCore

/// §5.1/§5.4: an airport from the bundled OurAirports dataset, filtered to
/// scheduled-service fields with a known ICAO code (§5.1's flight resolution keys on
/// ICAO; a row with no ICAO code can't be looked up by one).
public struct AirportRecord: Sendable, Equatable {
    public enum Kind: UInt8, Sendable, Equatable {
        case largeAirport = 0
        case mediumAirport = 1
        case smallAirport = 2
        case heliport = 3
        case seaplaneBase = 4
        case balloonport = 5
        case closed = 6
        case unknown = 255

        /// OurAirports' own `type` column values.
        public init(ourAirportsType: String) {
            switch ourAirportsType {
            case "large_airport": self = .largeAirport
            case "medium_airport": self = .mediumAirport
            case "small_airport": self = .smallAirport
            case "heliport": self = .heliport
            case "seaplane_base": self = .seaplaneBase
            case "balloonport": self = .balloonport
            case "closed": self = .closed
            default: self = .unknown
            }
        }
    }

    public let icao: String
    public let iata: String?
    public let name: String
    public let kind: Kind
    public let coordinate: Coordinate
    public let elevationMetres: Double
    public let municipality: String
    public let isoCountry: String

    public init(
        icao: String, iata: String?, name: String, kind: Kind,
        coordinate: Coordinate, elevationMetres: Double, municipality: String, isoCountry: String
    ) {
        self.icao = icao; self.iata = iata; self.name = name; self.kind = kind
        self.coordinate = coordinate; self.elevationMetres = elevationMetres
        self.municipality = municipality; self.isoCountry = isoCountry
    }
}

extension AirportRecord {
    func write(to writer: inout BinaryDatasetWriter) {
        writer.writeDouble(coordinate.latitude)
        writer.writeDouble(coordinate.longitude)
        writer.writeDouble(elevationMetres)
        writer.writeString(name)
        writer.writeString(icao)
        writer.writeString(iata ?? "")
        writer.writeUInt8(kind.rawValue)
        writer.writeString(municipality)
        writer.writeString(isoCountry)
    }

    static func read(from reader: inout BinaryDatasetReader) throws -> AirportRecord {
        let latitude = try reader.readDouble()
        let longitude = try reader.readDouble()
        let elevation = try reader.readDouble()
        let name = try reader.readString()
        let icao = try reader.readString()
        let iata = try reader.readString()
        let kindRaw = try reader.readUInt8()
        let municipality = try reader.readString()
        let isoCountry = try reader.readString()
        return AirportRecord(
            icao: icao, iata: iata.isEmpty ? nil : iata, name: name,
            kind: AirportRecord.Kind(rawValue: kindRaw) ?? .unknown,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            elevationMetres: elevation, municipality: municipality, isoCountry: isoCountry
        )
    }
}
