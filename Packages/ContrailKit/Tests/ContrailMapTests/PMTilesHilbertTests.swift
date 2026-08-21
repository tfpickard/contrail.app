import Testing
@testable import ContrailMap

/// Verified against the exact reference table from the PMTiles v3 spec, not derived
/// independently -- getting this wrong wouldn't cause a crash, it would cause tile
/// lookups to silently resolve to the *wrong* tile.
struct PMTilesHilbertTests {
    @Test func matchesTheSpecsOwnReferenceTable() {
        #expect(PMTilesHilbert.tileId(z: 0, x: 0, y: 0) == 0)
        #expect(PMTilesHilbert.tileId(z: 1, x: 0, y: 0) == 1)
        #expect(PMTilesHilbert.tileId(z: 1, x: 0, y: 1) == 2)
        #expect(PMTilesHilbert.tileId(z: 1, x: 1, y: 1) == 3)
        #expect(PMTilesHilbert.tileId(z: 1, x: 1, y: 0) == 4)
        #expect(PMTilesHilbert.tileId(z: 2, x: 0, y: 0) == 5)
    }

    @Test func idsAreUniqueAcrossAWholeZoomLevel() {
        let z: UInt8 = 4
        let n = UInt64(1) << z
        var seen = Set<UInt64>()
        for x in 0..<n {
            for y in 0..<n {
                let id = PMTilesHilbert.tileId(z: z, x: x, y: y)
                #expect(!seen.contains(id), "duplicate tile id at z=\(z) x=\(x) y=\(y)")
                seen.insert(id)
            }
        }
        #expect(seen.count == Int(n * n))
    }

    @Test func higherZoomLevelsProduceLargerIdRanges() {
        // Every tile at zoom z+1 must have a strictly larger id than every tile at
        // zoom z -- the "cumulative offset per zoom level" property the spec
        // describes.
        let maxIdAtZ3 = (0..<8).flatMap { x in (0..<8).map { y in PMTilesHilbert.tileId(z: 3, x: x, y: y) } }.max()!
        let minIdAtZ4 = PMTilesHilbert.tileId(z: 4, x: 0, y: 0)
        #expect(minIdAtZ4 > maxIdAtZ3)
    }
}
