import Foundation
import ContrailCore

/// A point projected onto the unit sphere in Earth-Centered, Earth-Fixed Cartesian
/// coordinates. Euclidean distance here is monotonic with great-circle angular
/// distance (`d² = 2 − 2cos θ` for points on a unit sphere), so nearest-Euclidean-
/// neighbor in this space is exactly nearest-great-circle-neighbor — a 3D k-d tree
/// over ECEF avoids every antimeridian/pole edge case a naive lat/lon tree would hit.
private struct ECEFPoint: Sendable {
    let x: Double, y: Double, z: Double

    init(_ c: Coordinate) {
        let φ = c.latitude.degreesToRadians
        let λ = c.longitude.degreesToRadians
        x = cos(φ) * cos(λ)
        y = cos(φ) * sin(λ)
        z = sin(φ)
    }

    func squaredDistance(to other: ECEFPoint) -> Double {
        let dx = x - other.x, dy = y - other.y, dz = z - other.z
        return dx * dx + dy * dy + dz * dz
    }

    subscript(axis: Int) -> Double {
        switch axis % 3 {
        case 0: return x
        case 1: return y
        default: return z
        }
    }
}

/// A nearest-neighbor lookup over geographic points, backed by a 3D k-d tree in ECEF
/// space (see `ECEFPoint`). Used by `ContrailData` for nearest-airport and
/// nearest-populated-place queries — §5.6 requires "nearest city" always be reported
/// with bearing and distance, not just a name, so both are computed here at query
/// time via `VincentyGeodesic` on the winning candidate only (the tree itself only
/// needs to prune correctly, not report distance precisely).
public struct GeoKDTree<Payload: Sendable>: Sendable {
    private indirect enum Node: Sendable {
        case leaf
        case branch(point: ECEFPoint, coordinate: Coordinate, payload: Payload, axis: Int, left: Node, right: Node)
    }

    private let root: Node
    public let count: Int

    public init(points: [(coordinate: Coordinate, payload: Payload)]) {
        count = points.count
        let entries = points.map { (ECEFPoint($0.coordinate), $0.coordinate, $0.payload) }
        root = Self.build(entries, depth: 0)
    }

    private static func build(
        _ entries: [(ECEFPoint, Coordinate, Payload)],
        depth: Int
    ) -> Node {
        guard !entries.isEmpty else { return .leaf }
        let axis = depth % 3
        let sorted = entries.sorted { $0.0[axis] < $1.0[axis] }
        let medianIndex = sorted.count / 2
        let median = sorted[medianIndex]
        let left = Array(sorted[..<medianIndex])
        let right = Array(sorted[(medianIndex + 1)...])
        return .branch(
            point: median.0,
            coordinate: median.1,
            payload: median.2,
            axis: axis,
            left: build(left, depth: depth + 1),
            right: build(right, depth: depth + 1)
        )
    }

    /// The result of a nearest-neighbor query: the matched payload, its coordinate,
    /// and the true (Vincenty) bearing and distance from the query point to it.
    public struct NearestResult: Sendable {
        public let payload: Payload
        public let coordinate: Coordinate
        public let bearing: Double   // degrees true, from query point to match
        public let distance: Double  // metres
    }

    /// Finds the nearest point to `query`. Returns `nil` only if the tree is empty.
    public func nearest(to query: Coordinate) -> NearestResult? {
        let target = ECEFPoint(query)
        var best: (point: ECEFPoint, coordinate: Coordinate, payload: Payload, distSq: Double)?

        func search(_ node: Node) {
            guard case let .branch(point, coordinate, payload, axis, left, right) = node else { return }

            let distSq = target.squaredDistance(to: point)
            if best == nil || distSq < best!.distSq {
                best = (point, coordinate, payload, distSq)
            }

            let delta = target[axis] - point[axis]
            let nearSide = delta < 0 ? left : right
            let farSide = delta < 0 ? right : left

            search(nearSide)

            // Only descend into the far side if the splitting plane is closer than
            // the current best candidate — the standard k-d tree pruning bound.
            if delta * delta < (best?.distSq ?? .infinity) {
                search(farSide)
            }
        }

        search(root)
        guard let best else { return nil }

        // Report true bearing/distance via Vincenty on the single winning candidate.
        guard let geodesic = try? VincentyGeodesic.inverse(from: query, to: best.coordinate) else {
            return nil
        }
        return NearestResult(
            payload: best.payload,
            coordinate: best.coordinate,
            bearing: geodesic.initialBearing,
            distance: geodesic.distance
        )
    }

    /// Every point within `radius` metres of `query` -- §5.5's divert planner needs
    /// "every reachable airport," not just the closest one. `radius` is converted to
    /// the equivalent squared ECEF chord distance once, up front, so the search's
    /// per-node pruning bound is a cheap comparison, not a per-candidate geodesic
    /// call; Vincenty only runs on points that actually pass the coarse bound.
    public func within(radius: Double, of query: Coordinate) -> [NearestResult] {
        let target = ECEFPoint(query)
        // Chord length for a central angle θ on a unit sphere is 2·sin(θ/2); Earth's
        // mean radius converts the surface distance `radius` to that angle.
        let angularRadius = radius / WGS84.meanRadius
        let chordRadius = 2 * sin(angularRadius / 2)
        let chordRadiusSq = chordRadius * chordRadius

        var candidates: [(point: ECEFPoint, coordinate: Coordinate, payload: Payload)] = []

        func search(_ node: Node) {
            guard case let .branch(point, coordinate, payload, axis, left, right) = node else { return }

            if target.squaredDistance(to: point) <= chordRadiusSq {
                candidates.append((point, coordinate, payload))
            }

            let delta = target[axis] - point[axis]
            let nearSide = delta < 0 ? left : right
            let farSide = delta < 0 ? right : left

            search(nearSide)
            if delta * delta <= chordRadiusSq {
                search(farSide)
            }
        }

        search(root)

        // Precise distance/bearing (and the final radius cut) via Vincenty, only on
        // the small candidate set the coarse ECEF bound already narrowed down to.
        return candidates.compactMap { candidate in
            guard let geodesic = try? VincentyGeodesic.inverse(from: query, to: candidate.coordinate),
                  geodesic.distance <= radius
            else { return nil }
            return NearestResult(
                payload: candidate.payload, coordinate: candidate.coordinate,
                bearing: geodesic.initialBearing, distance: geodesic.distance
            )
        }
    }
}
