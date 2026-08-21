import Foundation
import ContrailCore
import ContrailGeo

/// §5.4's "which ARTCC am I in" lookup. A linear scan over ~40 polygons (2,300
/// vertices total) per query — no spatial index needed at this scale; the whole
/// dataset is smaller than one k-d tree node's bookkeeping would cost.
public struct ARTCCBoundaryIndex: Sendable {
    public let boundaries: [ARTCCBoundary]

    public init(boundaries: [ARTCCBoundary]) {
        self.boundaries = boundaries
    }

    public init(data: Data) throws {
        let boundaries = try DatasetFile.read(data, expecting: .artccBoundaries, decode: ARTCCBoundary.read)
        self.init(boundaries: boundaries)
    }

    public static func compile(boundaries: [ARTCCBoundary]) -> Data {
        DatasetFile.write(records: boundaries, kind: .artccBoundaries) { boundary, writer in
            boundary.write(to: &writer)
        }
    }

    /// The ARTCC whose boundary at `tier` contains `coordinate`, if any. A position
    /// can legitimately be in none (outside all published boundaries, e.g. over
    /// international waters this dataset doesn't cover) or, at a boundary seam,
    /// arguably more than one -- the first match in publication order wins, which is
    /// an honest "some answer, not a promise of exactness at the seam," not a claim
    /// of authoritative jurisdiction.
    public func boundary(containing coordinate: Coordinate, tier: ARTCCBoundary.AltitudeTier) -> ARTCCBoundary? {
        boundaries.first { $0.altitudeTier == tier && PointInPolygon.contains(coordinate, polygon: $0.vertices) }
    }

    public var count: Int { boundaries.count }
}
