import ContrailCore
import ContrailData

/// Compiles FAA NASR's `ARB_BASE.csv`/`ARB_SEG.csv` (public domain, same 28-day
/// subscription as `NavFixCompiler`) into `ARTCCBoundary` polygons. `ARB_BASE`
/// names each boundary; `ARB_SEG` gives its vertices as one row per point, grouped
/// by `(LOCATION_ID, ALTITUDE)` and ordered by `POINT_SEQ` -- filtered here to
/// `TYPE == "ARTCC"` specifically, since `ARB_SEG` also carries FIR/CTA/UTA
/// boundaries for airspace this app's ARTCC-jurisdiction feature doesn't model.
enum ARTCCBoundaryCompiler {
    static func compile(baseCSV: String, segmentsCSV: String) -> [ARTCCBoundary] {
        let names = parseNames(baseCSV)
        let rows = CSVParser.parse(segmentsCSV)
        guard let header = rows.first else { return [] }
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func field(_ row: [String], _ name: String) -> String? {
            guard let index = columnIndex[name], index < row.count else { return nil }
            let value = row[index]
            return value.isEmpty ? nil : value
        }

        struct Vertex { let seq: Int; let coordinate: Coordinate }
        var pointsByGroup: [String: (locationID: String, altitude: String, vertices: [Vertex])] = [:]

        for row in rows.dropFirst() where row.count > 1 {
            guard field(row, "TYPE") == "ARTCC" else { continue }
            guard let locationID = field(row, "LOCATION_ID") else { continue }
            guard let altitude = field(row, "ALTITUDE") else { continue }
            guard let seq = field(row, "POINT_SEQ").flatMap(Int.init) else { continue }
            guard let latitude = field(row, "LAT_DECIMAL").flatMap(Double.init) else { continue }
            guard let longitude = field(row, "LONG_DECIMAL").flatMap(Double.init) else { continue }

            let key = "\(locationID)|\(altitude)"
            var group = pointsByGroup[key] ?? (locationID, altitude, [])
            group.vertices.append(Vertex(seq: seq, coordinate: Coordinate(latitude: latitude, longitude: longitude)))
            pointsByGroup[key] = group
        }

        return pointsByGroup.values.compactMap { group in
            guard let tier = ARTCCBoundary.AltitudeTier(rawValue: group.altitude) else { return nil }
            let ordered = group.vertices.sorted { $0.seq < $1.seq }.map(\.coordinate)
            guard ordered.count >= 3 else { return nil } // not a real polygon
            return ARTCCBoundary(
                id: group.locationID, name: names[group.locationID] ?? group.locationID,
                altitudeTier: tier, vertices: ordered
            )
        }
    }

    private static func parseNames(_ csv: String) -> [String: String] {
        let rows = CSVParser.parse(csv)
        guard let header = rows.first else { return [:] }
        let columnIndex = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })

        func field(_ row: [String], _ name: String) -> String? {
            guard let index = columnIndex[name], index < row.count else { return nil }
            let value = row[index]
            return value.isEmpty ? nil : value
        }

        var names: [String: String] = [:]
        for row in rows.dropFirst() where row.count > 1 {
            guard field(row, "LOCATION_TYPE") == "ARTCC" else { continue }
            guard let id = field(row, "LOCATION_ID") else { continue }
            names[id] = field(row, "LOCATION_NAME") ?? id
        }
        return names
    }
}
