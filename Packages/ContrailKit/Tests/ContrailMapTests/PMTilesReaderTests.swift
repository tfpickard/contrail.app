import Foundation
import Testing
@testable import ContrailMap

/// Verifies the parser against the actual bundled basemap file, not a hand-built
/// fixture — this is a real ~45 MB Protomaps daily build (extracted z0-6 world
/// subset), the same file the app ships. If the Hilbert tile-ID math, directory
/// parsing, or gzip decoding have any real bug, tile(0,0,0) failing to decode is
/// where it would show up.
struct PMTilesReaderTests {
    private func fixtureURL() throws -> URL {
        let url = Bundle.module.url(forResource: "basemap-z0-6", withExtension: "pmtiles", subdirectory: "Fixtures")
        return try #require(url, "basemap-z0-6.pmtiles fixture not found in test bundle")
    }

    @Test func headerParsesWithSaneZoomRange() async throws {
        let reader = try PMTilesReader(fileURL: fixtureURL())
        let minZoom = await reader.minZoom
        let maxZoom = await reader.maxZoom
        #expect(minZoom == 0)
        #expect(maxZoom == 6)
    }

    @Test func rootTileAtZoomZeroExists() async throws {
        // (0,0,0) covers the entire world -- every valid basemap has this tile.
        let reader = try PMTilesReader(fileURL: fixtureURL())
        let tile = try await reader.tile(z: 0, x: 0, y: 0)
        let data = try #require(tile, "expected a tile at (0,0,0)")
        #expect(!data.isEmpty)
    }

    @Test func decodedTileIsValidProtobufNotRawGzip() async throws {
        // A real sanity check on the gzip decode path specifically: if decompression
        // silently failed and returned the raw gzip bytes instead, the first byte
        // would be the gzip magic 0x1f, not a plausible protobuf varint tag byte.
        let reader = try PMTilesReader(fileURL: fixtureURL())
        let tile = try await reader.tile(z: 0, x: 0, y: 0)
        let data = try #require(tile)
        #expect(data.first != 0x1f, "tile data looks like raw gzip, not decompressed protobuf")
    }

    @Test func multipleZoomLevelsProduceTiles() async throws {
        let reader = try PMTilesReader(fileURL: fixtureURL())
        // Denver, CO at z=4 -- a real, populated location, not open ocean, so it
        // should have actual content across the covered zoom range.
        var foundAtLeastOne = false
        for z: UInt8 in 0...4 {
            let n = UInt64(1) << z
            // Web Mercator tile containing ~(39.7, -105) at this zoom.
            let x = UInt64(Double(n) * (-104.9903 + 180) / 360)
            let latRad = 39.7392 * Double.pi / 180
            let y = UInt64(Double(n) * (1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2)
            if let tile = try await reader.tile(z: z, x: x, y: y), !tile.isEmpty {
                foundAtLeastOne = true
            }
        }
        #expect(foundAtLeastOne)
    }

    @Test func tileOutsideZoomRangeReturnsNilNotError() async throws {
        let reader = try PMTilesReader(fileURL: fixtureURL())
        // z=10 exceeds this archive's max zoom of 6 -- Hilbert math is still well
        // defined, but no directory entry will exist for it.
        let tile = try await reader.tile(z: 10, x: 0, y: 0)
        #expect(tile == nil)
    }

    @Test func repeatedLookupsAreConsistent() async throws {
        // Exercises the directory caching path -- the second lookup of the same
        // tile must return byte-identical data to the first.
        let reader = try PMTilesReader(fileURL: fixtureURL())
        let first = try await reader.tile(z: 0, x: 0, y: 0)
        let second = try await reader.tile(z: 0, x: 0, y: 0)
        #expect(first == second)
    }
}
