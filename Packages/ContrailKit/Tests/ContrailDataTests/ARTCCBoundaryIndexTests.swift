import Foundation
import Testing
import ContrailCore
@testable import ContrailData

struct ARTCCBoundaryIndexTests {
    private let square: [Coordinate] = [
        Coordinate(latitude: 30, longitude: -110),
        Coordinate(latitude: 30, longitude: -100),
        Coordinate(latitude: 40, longitude: -100),
        Coordinate(latitude: 40, longitude: -110),
    ]

    private var zabLike: ARTCCBoundary {
        ARTCCBoundary(id: "ZAB", name: "ALBUQUERQUE", altitudeTier: .high, vertices: square)
    }
    private var zdvLike: ARTCCBoundary {
        ARTCCBoundary(
            id: "ZDV", name: "DENVER", altitudeTier: .high,
            vertices: [
                Coordinate(latitude: 40, longitude: -110),
                Coordinate(latitude: 40, longitude: -100),
                Coordinate(latitude: 50, longitude: -100),
                Coordinate(latitude: 50, longitude: -110),
            ]
        )
    }

    @Test func findsTheBoundaryContainingAPosition() {
        let index = ARTCCBoundaryIndex(boundaries: [zabLike, zdvLike])
        let insideZAB = Coordinate(latitude: 35, longitude: -105)
        #expect(index.boundary(containing: insideZAB, tier: .high)?.id == "ZAB")
        let insideZDV = Coordinate(latitude: 45, longitude: -105)
        #expect(index.boundary(containing: insideZDV, tier: .high)?.id == "ZDV")
    }

    @Test func returnsNilOutsideAllBoundaries() {
        let index = ARTCCBoundaryIndex(boundaries: [zabLike, zdvLike])
        #expect(index.boundary(containing: Coordinate(latitude: 0, longitude: 0), tier: .high) == nil)
    }

    @Test func tierMismatchDoesNotMatch() {
        // Both boundaries are `.high` in this fixture -- a `.low` query over the
        // same position must find nothing, not silently ignore the tier.
        let index = ARTCCBoundaryIndex(boundaries: [zabLike, zdvLike])
        let insideZAB = Coordinate(latitude: 35, longitude: -105)
        #expect(index.boundary(containing: insideZAB, tier: .low) == nil)
    }

    @Test func compileThenReadRoundTrips() throws {
        let originals = [zabLike, zdvLike]
        let data = ARTCCBoundaryIndex.compile(boundaries: originals)
        let index = try ARTCCBoundaryIndex(data: data)
        #expect(index.count == 2)
        #expect(index.boundaries.contains(zabLike))
        #expect(index.boundaries.contains(zdvLike))
    }
}
