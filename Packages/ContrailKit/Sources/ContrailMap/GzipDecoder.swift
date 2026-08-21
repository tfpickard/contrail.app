import Foundation
import Compression

/// Decodes gzip (RFC 1952) data using Apple's `Compression` framework rather than
/// linking zlib directly — no SwiftPM system-library-target setup needed.
/// `COMPRESSION_ZLIB` is Apple's (confusingly named) algorithm identifier for *raw*
/// DEFLATE, not the zlib-wrapped container format — so this parses the gzip header
/// and trailer by hand to isolate the raw DEFLATE payload, then hands only that to
/// `compression_decode_buffer`.
enum GzipDecoder {
    enum GzipError: Error {
        case notGzip
        case truncated
        case decodeFailed
    }

    static func decode(_ data: Data) throws -> Data {
        guard data.count >= 18 else { throw GzipError.truncated } // 10-byte header + empty deflate block + 8-byte trailer, minimum
        let bytes = [UInt8](data)

        guard bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw GzipError.notGzip // magic + CM=8 (deflate)
        }
        let flags = bytes[3]
        var offset = 10 // fixed header: magic(2) + CM(1) + FLG(1) + MTIME(4) + XFL(1) + OS(1)

        // FEXTRA
        if flags & 0x04 != 0 {
            guard offset + 2 <= bytes.count else { throw GzipError.truncated }
            let extraLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + extraLength
        }
        // FNAME: null-terminated string
        if flags & 0x08 != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FCOMMENT: null-terminated string
        if flags & 0x10 != 0 {
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC
        if flags & 0x02 != 0 {
            offset += 2
        }
        guard offset < bytes.count - 8 else { throw GzipError.truncated }

        let deflateData = bytes[offset..<(bytes.count - 8)]
        // The 8-byte trailer is CRC32 (4 bytes) *then* ISIZE (4 bytes) -- in that
        // order (RFC 1952 §2.3.1). ISIZE (the uncompressed size mod 2^32 — exactly
        // what's needed to size the destination buffer up front, since
        // compression_decode_buffer doesn't grow its output dynamically) is
        // therefore the *last* 4 bytes of the file, not the first 4 of the trailer —
        // a real bug caught by testing against the actual bundled basemap file:
        // reading the CRC32 position as ISIZE produced a nonsense multi-gigabyte
        // "size" and a decode failure that had nothing to do with the decompression
        // itself.
        let trailerStart = bytes.count - 8
        let isizeStart = trailerStart + 4
        let uncompressedSize = UInt32(bytes[isizeStart]) | (UInt32(bytes[isizeStart + 1]) << 8)
            | (UInt32(bytes[isizeStart + 2]) << 16) | (UInt32(bytes[isizeStart + 3]) << 24)

        guard uncompressedSize > 0 else { return Data() }

        var destination = [UInt8](repeating: 0, count: Int(uncompressedSize))
        let decodedCount = Array(deflateData).withUnsafeBufferPointer { srcBuffer -> Int in
            destination.withUnsafeMutableBufferPointer { dstBuffer -> Int in
                compression_decode_buffer(
                    dstBuffer.baseAddress!, dstBuffer.count,
                    srcBuffer.baseAddress!, srcBuffer.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == Int(uncompressedSize) else { throw GzipError.decodeFailed }
        return Data(destination)
    }
}
