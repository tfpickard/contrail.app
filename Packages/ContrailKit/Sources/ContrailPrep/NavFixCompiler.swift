import ContrailCore
import ContrailData

/// Compiles FAA NASR's 28-day CSV subscriber files (public domain,
/// https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/)
/// into `NavFixRecord`s. `FIX_BASE.csv` and `NAV_BASE.csv` both already publish
/// decimal-degree lat/lon (`LAT_DECIMAL`/`LONG_DECIMAL`) alongside the DMS columns —
/// no DMS parsing needed, unlike a lot of other aeronautical data.
enum NavFixCompiler {
    static func compileFixes(csv text: String) -> [NavFixRecord] {
        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return [] }
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func field(_ row: [String], _ name: String) -> String? {
            guard let index = columnIndex[name], index < row.count else { return nil }
            let value = row[index]
            return value.isEmpty ? nil : value
        }

        var records: [NavFixRecord] = []
        for row in rows.dropFirst() where row.count > 1 {
            guard let id = field(row, "FIX_ID") else { continue }
            guard let latitude = field(row, "LAT_DECIMAL").flatMap(Double.init) else { continue }
            guard let longitude = field(row, "LONG_DECIMAL").flatMap(Double.init) else { continue }

            records.append(NavFixRecord(
                id: id, kind: .fix, navaidType: nil, name: nil,
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                artccHigh: field(row, "ARTCC_ID_HIGH"), artccLow: field(row, "ARTCC_ID_LOW"),
                frequency: nil
            ))
        }
        return records
    }

    /// `SHUTDOWN` navaids are excluded -- they're published in NASR as a decommission
    /// record, not a real point to route by. Everything still `OPERATIONAL *` (IFR,
    /// VFR-only, or restricted) is kept: a restricted navaid is still a real,
    /// identifiable point along the route, just not one to legally navigate by.
    static func compileNavaids(csv text: String) -> [NavFixRecord] {
        let rows = CSVParser.parse(text)
        guard let header = rows.first else { return [] }
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func field(_ row: [String], _ name: String) -> String? {
            guard let index = columnIndex[name], index < row.count else { return nil }
            let value = row[index]
            return value.isEmpty ? nil : value
        }

        var records: [NavFixRecord] = []
        for row in rows.dropFirst() where row.count > 1 {
            guard field(row, "NAV_STATUS")?.hasPrefix("OPERATIONAL") == true else { continue }
            guard let id = field(row, "NAV_ID") else { continue }
            guard let latitude = field(row, "LAT_DECIMAL").flatMap(Double.init) else { continue }
            guard let longitude = field(row, "LONG_DECIMAL").flatMap(Double.init) else { continue }

            records.append(NavFixRecord(
                id: id, kind: .navaid,
                navaidType: field(row, "NAV_TYPE"), name: field(row, "NAME"),
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                artccHigh: field(row, "HIGH_ALT_ARTCC_ID"), artccLow: field(row, "LOW_ALT_ARTCC_ID"),
                frequency: field(row, "FREQ").flatMap(Double.init)
            ))
        }
        return records
    }
}
