import Foundation

/// §7.2/pushback #10: "ImageIO exposes no first-class XMP writer for JPEG; the
/// packet must be constructed and injected as an APP1 segment by hand." This is
/// that hand-injection, done directly on the JPEG byte stream that `ImageIO` has
/// already written the EXIF/IPTC tiers into (see `PhotoMetadataWriter`).
///
/// JPEG structure: `SOI` (`FFD8`), then a sequence of marker segments (`FF` + marker
/// byte + big-endian 2-byte length + payload), until `SOS` (`FFDA`) begins the
/// entropy-coded scan data. This inserts a new APP1 segment (identified by the
/// `http://ns.adobe.com/xap/1.0/` null-terminated ASCII prefix XMP readers look
/// for) immediately after any existing `APPn` segments (JFIF/EXIF) and before the
/// first non-`APPn` marker -- the conventional placement real-world tools (Adobe's
/// own, ExifTool) use, so readers that only look at the first APP1 for EXIF and a
/// later one for XMP find both where they expect them.
public enum JPEGSegmentInjector {
    public enum InjectionError: Error, Equatable {
        case notAJPEG
        case truncated
        case xmpPacketTooLarge
    }

    private static let xmpIdentifier: [UInt8] = Array("http://ns.adobe.com/xap/1.0/\0".utf8)
    private static let app1Marker: UInt8 = 0xE1

    public static func injectXMP(_ xmpPacket: String, intoJPEG jpegData: Data) throws -> Data {
        var bytes = [UInt8](jpegData)
        guard bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else {
            throw InjectionError.notAJPEG
        }

        let insertionOffset = try findInsertionOffset(in: bytes)

        let xmpContent = Array(xmpPacket.utf8)
        let payloadLength = xmpIdentifier.count + xmpContent.count
        let segmentLength = payloadLength + 2 // the length field itself counts toward the total
        guard segmentLength <= 0xFFFF else { throw InjectionError.xmpPacketTooLarge }

        var segment: [UInt8] = [0xFF, app1Marker, UInt8(segmentLength >> 8), UInt8(segmentLength & 0xFF)]
        segment.append(contentsOf: xmpIdentifier)
        segment.append(contentsOf: xmpContent)

        bytes.insert(contentsOf: segment, at: insertionOffset)
        return Data(bytes)
    }

    /// Walks marker segments starting right after `SOI`, skipping over any `APPn`
    /// segments (`FFE0`...`FFEF`) -- the offset where that run ends is where the new
    /// APP1 belongs. Stops (and returns that offset) at the first non-`APPn` marker,
    /// which includes `SOS` for a JPEG with no `APPn` segments at all.
    private static func findInsertionOffset(in bytes: [UInt8]) throws -> Int {
        var offset = 2 // past SOI
        while true {
            // Only 2 bytes (FF + marker) are guaranteed to exist for every marker --
            // EOI (D9) and other no-length markers can legitimately be the last
            // thing in the stream, with no length field to require 4 bytes for.
            guard offset + 2 <= bytes.count, bytes[offset] == 0xFF else {
                throw InjectionError.truncated
            }
            let marker = bytes[offset + 1]

            // Markers with no length field: TEM (01), RST0-7 (D0-D7). SOI/EOI don't
            // recur mid-stream in a well-formed file; if encountered, treat as the
            // end of the marker-segment run.
            if marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) {
                offset += 2
                continue
            }

            guard marker >= 0xE0, marker <= 0xEF else {
                // Not an APPn segment -- this is the insertion point.
                return offset
            }

            guard offset + 4 <= bytes.count else { throw InjectionError.truncated }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard length >= 2, offset + 2 + length <= bytes.count else { throw InjectionError.truncated }
            offset += 2 + length
        }
    }
}
