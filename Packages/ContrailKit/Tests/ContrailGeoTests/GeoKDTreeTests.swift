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

    // §5.5's divert planner needs "every reachable airport within N metres," not
    // just the closest one. The radius cutoff is derived from real Vincenty
    // distances computed here, not a hand-guessed real-world estimate -- Ely's
    // nearest and next-nearest neighbors by great-circle distance aren't the
    // geographically "obvious" ones (Salt Lake City is actually closer to Ely than
    // Reno is), so a memorized-distance assumption would have picked the wrong cut.
    @Test func withinRadiusFindsExactlyThePointsInRangeNoMoreNoLess() throws {
        let query = Coordinate(latitude: 39.2474, longitude: -114.8887) // Ely itself
        let distances = try places.map { coordinate, name in
            (name, try VincentyGeodesic.inverse(from: query, to: coordinate).distance)
        }.sorted { $0.1 < $1.1 }

        // Cut the radius exactly between the 2nd and 3rd closest place, so the
        // in-range set is unambiguous regardless of which places those turn out to be.
        let radius = (distances[1].1 + distances[2].1) / 2
        let expectedInRange = Set(distances.prefix(2).map(\.0))
        let expectedOutOfRange = Set(distances.dropFirst(2).map(\.0))

        let tree = GeoKDTree(points: places.map { ($0.0, $0.1) })
        let results = tree.within(radius: radius, of: query)
        let names = Set(results.map(\.payload))

        #expect(names == expectedInRange)
        #expect(names.isDisjoint(with: expectedOutOfRange))
        for result in results {
            #expect(result.distance <= radius)
        }
    }

    @Test func withinRadiusOfZeroAtAnExactPointReturnsOnlyThatPoint() {
        let tree = GeoKDTree(points: places.map { ($0.0, $0.1) })
        let denver = Coordinate(latitude: 39.7392, longitude: -104.9903)
        let results = tree.within(radius: 1000, of: denver) // 1 km -- effectively "just here"
        #expect(results.map(\.payload) == ["Denver, Colorado"])
    }

    @Test func withinRadiusMatchesBruteForceOverManyRandomPoints() {
        var grid: [(Coordinate, Int)] = []
        var id = 0
        for latStep in stride(from: -60, through: 60, by: 7) {
            for lonStep in stride(from: -170, through: 170, by: 11) {
                grid.append((Coordinate(latitude: Double(latStep), longitude: Double(lonStep)), id))
                id += 1
            }
        }
        let tree = GeoKDTree(points: grid)
        let query = Coordinate(latitude: 39.86, longitude: -104.67)
        let radius = 2_000_000.0 // 2000 km

        let treeResult = Set(tree.within(radius: radius, of: query).map(\.payload))
        let bruteResult = Set(grid.compactMap { point -> Int? in
            let distance = (try? VincentyGeodesic.inverse(from: query, to: point.0).distance) ?? .infinity
            return distance <= radius ? point.1 : nil
        })
        #expect(treeResult == bruteResult)
    }
}
