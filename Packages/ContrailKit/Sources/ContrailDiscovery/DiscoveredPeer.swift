import Foundation

/// Everything `PassengerDiscoveryEngine` knows about one nearby peer, keyed by that
/// peer's current `BeaconPayload.sessionID` -- which is only stable for as long as
/// their app stays running, by design (see `BeaconPayload`'s own doc comment).
public struct DiscoveredPeer: Sendable, Equatable, Identifiable {
    public let id: UInt64
    public var disclosure: DisclosureState
    /// Populated only once `disclosure == .mutuallyAccepted` and the GATT read has
    /// completed -- `nil` before that is honest "haven't asked," not "asked and
    /// they said nothing."
    public var handshakeRecord: HandshakeRecord?
    public var avatarData: Data?
    public var lastSeen: Date
    public var rssi: Int?

    public init(
        id: UInt64,
        disclosure: DisclosureState = .presenceOnly,
        handshakeRecord: HandshakeRecord? = nil,
        avatarData: Data? = nil,
        lastSeen: Date,
        rssi: Int? = nil
    ) {
        self.id = id
        self.disclosure = disclosure
        self.handshakeRecord = handshakeRecord
        self.avatarData = avatarData
        self.lastSeen = lastSeen
        self.rssi = rssi
    }
}
