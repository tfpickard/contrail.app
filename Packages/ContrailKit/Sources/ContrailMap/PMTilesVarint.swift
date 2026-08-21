import Foundation

/// Protobuf-style LEB128 varint reading — verified against PMTiles' own reference
/// implementation (`js/src/index.ts`'s `readVarint`), not derived from the general
/// varint concept alone: PMTiles values can exceed 32 bits (large archives), so the
/// naive "stop at 5 bytes" version silently truncates on a big enough archive.
struct VarintReader {
    private let bytes: [UInt8]
    private(set) var position: Int

    init(_ data: Data, startingAt position: Int = 0) {
        self.bytes = [UInt8](data)
        self.position = position
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard position < bytes.count else { throw PMTilesError.truncated }
            let byte = bytes[position]
            position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            guard shift < 70 else { throw PMTilesError.malformedVarint }
        }
    }

    var isAtEnd: Bool { position >= bytes.count }
}

enum PMTilesError: Error, Equatable {
    case truncated
    case malformedVarint
    case badMagic
    case unsupportedVersion(UInt8)
    case tileNotFound
    case tooManyLeafHops
    case unsupportedCompression(PMTilesCompression)
}
