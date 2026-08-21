import Foundation
import ContrailCore
import ContrailGeo

/// §5.3's on-route fix/navaid lookup. Nearest-by-position (`nearest(to:)`) is the
/// k-d-tree-backed query; "every fix within N metres of the filed route" is
/// deliberately left to the caller as a linear scan over `records` — with ~70k
/// points and a route-relative check per point, that's still comfortably sub-second
/// on-device, done once at flight start (the route doesn't move), and it avoids
/// this module needing to know `FlightPlan`'s route-relative geometry at all.
public struct NavFixIndex: Sendable {
    public let records: [NavFixRecord]
    private let tree: GeoKDTree<NavFixRecord>

    public init(records: [NavFixRecord]) {
        self.records = records
        tree = GeoKDTree(points: records.map { ($0.coordinate, $0) })
    }

    public init(data: Data) throws {
        let records = try DatasetFile.read(data, expecting: .navFixes, decode: NavFixRecord.read)
        self.init(records: records)
    }

    public static func compile(records: [NavFixRecord]) -> Data {
        DatasetFile.write(records: records, kind: .navFixes) { record, writer in
            record.write(to: &writer)
        }
    }

    public func nearest(to coordinate: Coordinate) -> NavFixRecord? {
        tree.nearest(to: coordinate)?.payload
    }

    public var count: Int { records.count }
}
