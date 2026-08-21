import Foundation

/// Reads tiles from a local PMTiles v3 archive: header → root directory → (possibly
/// nested) leaf directories → tile bytes, decompressing as needed. An `actor`
/// deliberately — this is the shared lookup path for every concurrent tile request
/// the local HTTP server (`PMTilesHTTPServer`) handles, and actor isolation gives
/// that serialization for free rather than requiring manual synchronization around
/// the directory caches.
public actor PMTilesReader {
    private let data: Data
    private let header: PMTilesHeader
    private var rootDirectoryCache: [PMTilesEntry]?
    private var leafDirectoryCache: [UInt64: [PMTilesEntry]] = [:]

    public init(fileURL: URL) throws {
        // `.mappedIfSafe` -- this file is tens of MB; no reason to fully materialize
        // it in memory when only small slices (header, directories, one tile) are
        // ever actually touched per lookup.
        self.data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        self.header = try PMTilesHeader(data: data)
    }

    public var minZoom: UInt8 { header.minZoom }
    public var maxZoom: UInt8 { header.maxZoom }

    /// The raw (already decompressed) tile bytes for (z, x, y) — MVT protobuf data
    /// for a vector archive — or `nil` if the archive has no tile at that address
    /// (a legitimate, common case: sparse coverage at open ocean, or simply outside
    /// [minZoom, maxZoom]).
    public func tile(z: UInt8, x: UInt64, y: UInt64) throws -> Data? {
        let tileId = PMTilesHilbert.tileId(z: z, x: x, y: y)
        var directory = try rootDirectory()

        // The spec permits directory nesting beyond one leaf level in principle;
        // real archives (including this app's bundled basemap) never go past one.
        // A hop cap turns a malformed/adversarial archive into a thrown error
        // instead of an infinite loop.
        for _ in 0..<4 {
            guard let entry = PMTilesDirectoryCoding.findTile(directory, tileId: tileId) else {
                return nil
            }
            if entry.runLength == 0 {
                directory = try leafDirectory(offset: entry.offset, length: entry.length)
                continue
            }
            let start = Int(header.tileDataOffset) + Int(entry.offset)
            let end = start + Int(entry.length)
            guard end <= data.count else { throw PMTilesError.truncated }
            let rawTile = data.subdata(in: start..<end)
            return try decompress(rawTile, using: header.tileCompression)
        }
        throw PMTilesError.tooManyLeafHops
    }

    private func rootDirectory() throws -> [PMTilesEntry] {
        if let cached = rootDirectoryCache { return cached }
        let start = Int(header.rootDirectoryOffset)
        let end = start + Int(header.rootDirectoryLength)
        guard end <= data.count else { throw PMTilesError.truncated }
        let decompressed = try decompress(data.subdata(in: start..<end), using: header.internalCompression)
        let entries = try PMTilesDirectoryCoding.deserialize(decompressed)
        rootDirectoryCache = entries
        return entries
    }

    private func leafDirectory(offset: UInt64, length: UInt64) throws -> [PMTilesEntry] {
        if let cached = leafDirectoryCache[offset] { return cached }
        let start = Int(header.leafDirectoryOffset) + Int(offset)
        let end = start + Int(length)
        guard end <= data.count else { throw PMTilesError.truncated }
        let decompressed = try decompress(data.subdata(in: start..<end), using: header.internalCompression)
        let entries = try PMTilesDirectoryCoding.deserialize(decompressed)
        leafDirectoryCache[offset] = entries
        return entries
    }

    private func decompress(_ data: Data, using compression: PMTilesCompression) throws -> Data {
        switch compression {
        case .none, .unknown:
            return data
        case .gzip:
            return try GzipDecoder.decode(data)
        case .brotli, .zstd:
            throw PMTilesError.unsupportedCompression(compression)
        }
    }
}
