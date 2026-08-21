import Foundation

/// Compression codes from the PMTiles v3 spec, verified against the reference
/// implementation's `Compression` enum (`js/src/index.ts`) — `.unknown = 0`,
/// `.none = 1`, `.gzip = 2`, `.brotli = 3`, `.zstd = 4`. Only `.none`/`.gzip` are
/// handled; a `.brotli`/`.zstd` archive is out of scope (Protomaps' own basemap
/// builds use gzip).
enum PMTilesCompression: UInt8 {
    case unknown = 0
    case none = 1
    case gzip = 2
    case brotli = 3
    case zstd = 4
}

/// The 127-byte PMTiles v3 header. Byte offsets verified against the reference
/// implementation's `bytesToHeader` (`js/src/index.ts`), not just the prose spec —
/// the two agreed exactly on field layout when cross-checked.
struct PMTilesHeader {
    static let byteSize = 127

    let rootDirectoryOffset: UInt64
    let rootDirectoryLength: UInt64
    let leafDirectoryOffset: UInt64
    let leafDirectoryLength: UInt64
    let tileDataOffset: UInt64
    let tileDataLength: UInt64
    let internalCompression: PMTilesCompression
    let tileCompression: PMTilesCompression
    let minZoom: UInt8
    let maxZoom: UInt8

    init(data: Data) throws {
        guard data.count >= Self.byteSize else { throw PMTilesError.truncated }
        let bytes = [UInt8](data.prefix(Self.byteSize))

        // Matches the reference implementation's own check exactly: only the first
        // two magic bytes ("PM") are validated at runtime, not the full "PMTiles"
        // string some summaries of the spec describe.
        guard bytes[0] == 0x50, bytes[1] == 0x4D else { throw PMTilesError.badMagic }

        let version = bytes[7]
        guard version <= 3 else { throw PMTilesError.unsupportedVersion(version) }

        func u64(_ offset: Int) -> UInt64 {
            var value: UInt64 = 0
            for i in 0..<8 { value |= UInt64(bytes[offset + i]) << (8 * i) }
            return value
        }

        rootDirectoryOffset = u64(8)
        rootDirectoryLength = u64(16)
        leafDirectoryOffset = u64(40)
        leafDirectoryLength = u64(48)
        tileDataOffset = u64(56)
        tileDataLength = u64(64)
        internalCompression = PMTilesCompression(rawValue: bytes[97]) ?? .unknown
        tileCompression = PMTilesCompression(rawValue: bytes[98]) ?? .unknown
        minZoom = bytes[100]
        maxZoom = bytes[101]
    }
}
