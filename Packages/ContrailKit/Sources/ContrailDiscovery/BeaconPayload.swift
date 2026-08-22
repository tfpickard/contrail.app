import Foundation

/// ROADMAP 3a: "advertisement payload is 31 bytes total, leaving roughly 20 usable,
/// so the advertisement carries presence only, nothing more." This is that payload:
/// nine bytes, well inside budget, carrying nothing but "someone here runs this app."
public struct BeaconPayload: Sendable, Equatable {
    public static let protocolVersion: UInt8 = 1
    public static let encodedByteCount = 9

    /// Regenerated fresh every app launch, never persisted. A stable per-device
    /// identifier here would let two sightings be correlated across flights or
    /// across days -- nothing this feature needs, and exactly the kind of ambient
    /// tracking identifier the privacy design (ROADMAP 3a) exists to avoid.
    public let sessionID: UInt64

    public init(sessionID: UInt64) {
        self.sessionID = sessionID
    }

    public static func freshSessionID() -> UInt64 {
        UInt64.random(in: UInt64.min...UInt64.max)
    }

    /// Manual big-endian byte packing rather than `withUnsafeBytes` over `Data` --
    /// `Data`'s storage isn't guaranteed contiguous or aligned, and this is a
    /// 9-byte payload where correctness matters far more than the few cycles a
    /// bounds-checked loop costs.
    public var encoded: Data {
        var bytes: [UInt8] = [Self.protocolVersion]
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((sessionID >> UInt64(shift)) & 0xFF))
        }
        return Data(bytes)
    }

    public static func decode(_ data: Data) -> BeaconPayload? {
        let bytes = Array(data)
        guard bytes.count >= encodedByteCount, bytes[0] == protocolVersion else { return nil }
        var sessionID: UInt64 = 0
        for byte in bytes[1..<encodedByteCount] {
            sessionID = (sessionID << 8) | UInt64(byte)
        }
        return BeaconPayload(sessionID: sessionID)
    }
}
