import Foundation

/// ROADMAP 3a: "the hash means a given person's image is fetched exactly once,
/// ever." Keyed by `HandshakeRecord.avatarHash`, not by peer -- the same person
/// (same hash) sighted again, even after the app relaunches with a fresh
/// `BeaconPayload.sessionID`, still hits the cache instead of re-fetching.
public protocol AvatarCache: Sendable {
    func data(forHash hash: String) -> Data?
    func store(_ data: Data, forHash hash: String)
}

/// The default in-process cache. Not persisted to disk -- avatars are small, and a
/// cache that only needs to survive one flight (the scope `PassengerDiscoveryEngine`
/// operates in) doesn't need the durability a file would add complexity for.
public final class InMemoryAvatarCache: AvatarCache, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    public init() {}

    public func data(forHash hash: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[hash]
    }

    public func store(_ data: Data, forHash hash: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[hash] = data
    }
}
