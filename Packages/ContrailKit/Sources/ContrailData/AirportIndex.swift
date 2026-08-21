import Foundation
import ContrailCore
import ContrailGeo

/// §5.1/§5.4: an in-memory, queryable index over the compiled airport dataset —
/// exact lookup by ICAO/IATA code (flight resolution) and nearest-by-position (a
/// building block for 1.4's divert planning, not itself doing runway filtering).
public struct AirportIndex: Sendable {
    private let byICAO: [String: AirportRecord]
    private let byIATA: [String: AirportRecord]
    private let tree: GeoKDTree<AirportRecord>

    public init(records: [AirportRecord]) {
        var icaoMap: [String: AirportRecord] = [:]
        var iataMap: [String: AirportRecord] = [:]
        icaoMap.reserveCapacity(records.count)
        for record in records {
            icaoMap[record.icao] = record
            if let iata = record.iata { iataMap[iata] = record }
        }
        byICAO = icaoMap
        byIATA = iataMap
        tree = GeoKDTree(points: records.map { ($0.coordinate, $0) })
    }

    public init(data: Data) throws {
        let records = try DatasetFile.read(data, expecting: .airports, decode: AirportRecord.read)
        self.init(records: records)
    }

    /// Compiles `records` into the binary format `init(data:)` reads back —
    /// `ContrailPrep`'s counterpart, called after it parses OurAirports' CSV. The
    /// binary layout itself (`DatasetFile`, `BinaryDatasetWriter`) stays internal to
    /// this module; `ContrailPrep` only ever deals in `AirportRecord` values.
    public static func compile(records: [AirportRecord]) -> Data {
        DatasetFile.write(records: records, kind: .airports) { record, writer in
            record.write(to: &writer)
        }
    }

    public func airport(icao: String) -> AirportRecord? { byICAO[icao.uppercased()] }
    public func airport(iata: String) -> AirportRecord? { byIATA[iata.uppercased()] }

    public func nearest(to coordinate: Coordinate) -> AirportRecord? {
        tree.nearest(to: coordinate)?.payload
    }

    /// §5.5's divert planner: every airport within `radius` metres of `coordinate`,
    /// nearest first. Not itself glide-reach-aware -- the caller narrows this by
    /// each candidate's own elevation vs. current altitude.
    public func within(radius: Double, of coordinate: Coordinate) -> [GeoKDTree<AirportRecord>.NearestResult] {
        tree.within(radius: radius, of: coordinate).sorted { $0.distance < $1.distance }
    }

    public var count: Int { byICAO.count }
}
