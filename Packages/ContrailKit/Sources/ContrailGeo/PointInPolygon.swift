import ContrailCore

/// §5.4's ARTCC-jurisdiction lookup needs "is this position inside this boundary
/// polygon" — a standard ray-casting (even-odd rule) test on raw lat/lon. This is
/// deliberately *not* spherical: ARTCC boundaries (FAA NASR `ARB_SEG`) are already
/// published as a flat sequence of lat/lon vertices meant to be connected by straight
/// lines on a chart, not geodesics, and at ARTCC scale (hundreds of km) the
/// flat-plane approximation error is negligible next to the boundary's own
/// published precision.
///
/// **Known limitation:** this does not handle a polygon that crosses the
/// antimeridian (±180°) — Anchorage ARTCC's oceanic boundary segments can. A
/// position inside such a polygon near the dateline may misclassify. Flagged here
/// rather than silently wrong; fixing it needs longitude unwrapping specific to each
/// polygon's own extent, not a general one.
public enum PointInPolygon {
    /// `vertices` need not be explicitly closed (last point equal to first) — the
    /// edge from the last vertex back to the first is always implied.
    public static func contains(_ point: Coordinate, polygon vertices: [Coordinate]) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in 0..<vertices.count {
            let vi = vertices[i]
            let vj = vertices[j]
            let intersects = (vi.latitude > point.latitude) != (vj.latitude > point.latitude)
                && point.longitude < (vj.longitude - vi.longitude)
                    * (point.latitude - vi.latitude) / (vj.latitude - vi.latitude) + vi.longitude
            if intersects { inside.toggle() }
            j = i
        }
        return inside
    }
}
