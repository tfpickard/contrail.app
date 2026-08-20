import ContrailCore
import ContrailData

/// Compiles GeoNames' `cities1000` dump (https://download.geonames.org/export/dump/,
/// CC-BY 4.0 — the app must carry attribution) into `PlaceRecord`s. Tab-delimited,
/// no quoting, no header line; column order per GeoNames' own `readme.txt`, verified
/// against real data rather than trusted from memory (the Ely, Nevada row: population
/// 4134, admin1 "NV" — matches §5.6's own worked example).
enum PlaceCompiler {
    // 0-indexed column positions in the geonameid/name/asciiname/... layout.
    private static let nameColumn = 1
    private static let latitudeColumn = 4
    private static let longitudeColumn = 5
    private static let countryCodeColumn = 8
    private static let admin1Column = 10
    private static let populationColumn = 14

    static func compile(tsv text: String) -> [PlaceRecord] {
        var records: [PlaceRecord] = []
        text.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count > populationColumn else { return }
            guard let latitude = Double(fields[latitudeColumn]),
                  let longitude = Double(fields[longitudeColumn]) else { return }
            let population = UInt32(fields[populationColumn]) ?? 0

            records.append(PlaceRecord(
                name: fields[nameColumn],
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                countryCode: fields[countryCodeColumn],
                admin1Code: fields[admin1Column],
                population: population
            ))
        }
        return records
    }
}
