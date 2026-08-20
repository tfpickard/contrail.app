import ContrailCore
import ContrailData

/// Compiles OurAirports' `airports.csv` (https://ourairports.com/data/, public
/// domain) into `AirportRecord`s: filtered to `scheduled_service == "yes"` (§5 scope:
/// airports the pre-flight resolver and divert planner actually care about) with a
/// known ICAO code, since §5.1 keys flight resolution on ICAO — a row without one
/// can't be looked up by it.
enum AirportCompiler {
    static func compile(csv text: String) -> [AirportRecord] {
        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return [] }
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func field(_ row: [String], _ name: String) -> String? {
            guard let index = columnIndex[name], index < row.count else { return nil }
            let value = row[index]
            return value.isEmpty ? nil : value
        }

        var records: [AirportRecord] = []
        for row in rows.dropFirst() where row.count > 1 {
            guard field(row, "scheduled_service") == "yes" else { continue }
            guard let icao = field(row, "icao_code") else { continue }
            guard let latitude = field(row, "latitude_deg").flatMap(Double.init) else { continue }
            guard let longitude = field(row, "longitude_deg").flatMap(Double.init) else { continue }

            let name = field(row, "name") ?? icao
            let kind = AirportRecord.Kind(ourAirportsType: field(row, "type") ?? "")
            let elevationFeet = field(row, "elevation_ft").flatMap(Double.init) ?? 0

            records.append(AirportRecord(
                icao: icao,
                iata: field(row, "iata_code"),
                name: name,
                kind: kind,
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                elevationMetres: elevationFeet * 0.3048,
                municipality: field(row, "municipality") ?? "",
                isoCountry: field(row, "iso_country") ?? ""
            ))
        }
        return records
    }
}
