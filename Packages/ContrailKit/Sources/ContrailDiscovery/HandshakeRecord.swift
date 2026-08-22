import Foundation

/// ROADMAP 3a: "GATT for the handshake. First read returns a minimal record:
/// display name, a few generated stats, and a hash of the avatar. The discovery
/// screen is therefore instant." This is that record -- deliberately small (no
/// avatar bytes, no full `GeneratedProfileStats`), so a GATT characteristic read
/// stays a single round trip.
public struct HandshakeRecord: Sendable, Codable, Equatable {
    public let displayName: String
    public let flightsLogged: Int
    public let homeBaseICAO: String?
    /// `nil` means "no avatar set," distinct from "avatar exists but not yet
    /// fetched" -- the discovery screen shouldn't offer to fetch something that
    /// doesn't exist.
    public let avatarHash: String?

    public init(displayName: String, flightsLogged: Int, homeBaseICAO: String?, avatarHash: String?) {
        self.displayName = displayName
        self.flightsLogged = flightsLogged
        self.homeBaseICAO = homeBaseICAO
        self.avatarHash = avatarHash
    }

    public func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> HandshakeRecord {
        try JSONDecoder().decode(HandshakeRecord.self, from: data)
    }
}
