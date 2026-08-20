import Testing
import ContrailCore
@testable import ContrailGeo

struct GeoKDTreeTests {
    // The spec's own motivating example (§5.6): over the Great Basin, the nearest
    // city may be dozens of miles away, and the tree must still find it — and report
    // bearing and distance, not just a name.
    private let places: [(Coordinate, String)] = [
        ("Ely, Nevada", 39.2474, -114.8887),
        ("Denver, Colorado", 39.7392, -104.9903),
        ("Los Angeles, California", 34.0522, -118.2437),
        ("Salt Lake City, Utah", 40.7608, -111.8910),
        ("Reno, Nevada", 39.5296, -119.8138),
    ].map { (Coordinate(latitude: $0.1, longitude: $0.2), $0.0) }

    @Test func findsTheActuallyNearestPlace() {
        let tree = GeoKDTree(points: places.map { ($0.0, $0.1) })
        // A point in the middle of the Great Basin, closest to Ely among the set.
        let query = Coordinate(latitude: 39.3, longitude: -115.0)
        let result = tree.nearest(to: query)
        #expect(result?.payload == "Ely, Nevada")
        #expect(result!.distance > 0)
        #expect(result!.distance < 50_000) // within 50 km of the query
    }

    @Test func bearingAndDistanceAreNeverZeroForADistinctPoint() {
        let tree = GeoKDTree(points: places.map { ($0.0, $0.1) })
        let query = Coordinate(latitude: 36.5, longitude: -114.5) // over Nevada, mid-flight
        let result = tree.nearest(to: query)
        #expect(result != nil)
        #expect(result!.distance > 0)
        #expect(result!.bearing >= 0)
        #expect(result!.bearing < 360)
    }

    @Test func emptyTreeReturnsNil() {
        let tree = GeoKDTree<String>(points: [])
        #expect(tree.nearest(to: Coordinate(latitude: 0, longitude: 0)) == nil)
    }

    @Test func exactQueryPointReturnsItselfAtZeroDistance() {
        let denver = Coordinate(latitude: 39.7392, longitude: -104.9903)
        let tree = GeoKDTree(points: places.map { ($0.0, $0.1) })
        let result = tree.nearest(to: denver)
        #expect(result?.payload == "Denver, Colorado")
        #expect(result!.distance < 1.0) // effectively zero, floating-point noise only
    }

    @Test func correctnessAgainstBruteForceOverManyRandomPoints() {
        // Cross-check the k-d tree's pruning logic against a brute-force linear scan
        // over a larger, denser point set — the pruning bound (`delta*delta <
        // best.distSq`) is the part most likely to hide a bug that only shows up off
        // the tree's own median splits.
        var grid: [(Coordinate, Int)] = []
        var id = 0
        for latStep in stride(from: -60, through: 60, by: 7) {
            for lonStep in stride(from: -170, through: 170, by: 11) {
                grid.append((Coordinate(latitude: Double(latStep), longitude: Double(lonStep)), id))
                id += 1
            }
        }
        let tree = GeoKDTree(points: grid)

        func bruteForceNearest(to query: Coordinate) -> Int {
            grid.min { a, b in
                let da = try! VincentyGeodesic.inverse(from: query, to: a.0).distance
                let db = try! VincentyGeodesic.inverse(from: query, to: b.0).distance
                return da < db
            }!.1
        }

        let queries = [
            Coordinate(latitude: 39.86, longitude: -104.67),
            Coordinate(latitude: -33.87, longitude: 151.21),
            Coordinate(latitude: 51.51, longitude: -0.13),
            Coordinate(latitude: 0.5, longitude: 179.5),   // near antimeridian
            Coordinate(latitude: 89.0, longitude: 45.0),   // near the pole
        ]

        for query in queries {
            let treeResult = tree.nearest(to: query)?.payload
            let bruteResult = bruteForceNearest(to: query)
            #expect(treeResult == bruteResult, "mismatch at \(query)")
        }
    }
}
