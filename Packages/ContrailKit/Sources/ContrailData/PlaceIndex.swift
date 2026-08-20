import Foundation
import ContrailCore
import ContrailGeo

/// §5.6: the nearest-populated-place index — this is what actually plugs into
/// `Estimator.init`'s `nearestPlace` closure once a manifest's assets are loaded.
public struct PlaceIndex: Sendable {
    private let tree: GeoKDTree<PlaceRecord>

    public init(records: [PlaceRecord]) {
        tree = GeoKDTree(points: records.map { ($0.coordinate, $0) })
    }

    public init(data: Data) throws {
        let records = try DatasetFile.read(data, expecting: .places, decode: PlaceRecord.read)
        self.init(records: records)
    }

    /// `ContrailPrep`'s counterpart, called after it parses GeoNames' `cities1000`.
    public static func compile(records: [PlaceRecord]) -> Data {
        DatasetFile.write(records: records, kind: .places) { record, writer in
            record.write(to: &writer)
        }
    }

    /// A ready-made `nearestPlace` closure for `Estimator.init` — bearing and
    /// distance always accompany the name, per §5.6.
    public func nearestPlaceLookup() -> @Sendable (Coordinate) -> BearingToPlace? {
        { [tree] coordinate in
            guard let result = tree.nearest(to: coordinate) else { return nil }
            return BearingToPlace(name: result.payload.displayName, bearing: result.bearing, distance: result.distance)
        }
    }

    public func nearest(to coordinate: Coordinate) -> PlaceRecord? {
        tree.nearest(to: coordinate)?.payload
    }
}
