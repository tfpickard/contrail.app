import Foundation
import MultipeerConnectivity
import ContrailDiscovery

/// ROADMAP 3a: "bulk transfer over peer-to-peer Wi-Fi. MultipeerConnectivity...
/// negotiates over Bluetooth then brings up AWDL -- the same transport AirDrop
/// rides." This is that bulk-transfer half, used only for the avatar fetch (BLE
/// stays the beacon+handshake half, in `BLEDiscoveryController`).
///
/// Correlating a peer across the two frameworks is the real wrinkle: BLE and
/// MultipeerConnectivity discover peers through entirely separate mechanisms
/// (`CBPeripheral` vs. `MCPeerID`), so this transport encodes the same
/// `BeaconPayload.sessionID` BLE already established into the local `MCPeerID`'s
/// display name (`"contrail-<sessionID>"`) and matches on that string -- the two
/// frameworks never need to know about each other beyond this one shared number.
///
/// Verification limit: exercised locally between two Simulator instances over
/// Bonjour, which confirms the Multipeer wiring is at least reachable, but AWDL
/// (the real production path between two physical devices) has not been tested --
/// see `BLEDiscoveryController`'s own doc comment for the same caveat on BLE.
final class MultipeerAvatarTransport: NSObject, BulkTransferTransport, @unchecked Sendable {
    private static let serviceType = "contrail-av"
    private static let peerIDPrefix = "contrail-"

    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser

    private struct State {
        var discoveredPeersBySessionID: [UInt64: MCPeerID] = [:]
        var pendingConnections: [UInt64: CheckedContinuation<Void, Error>] = [:]
        var pendingAvatarRequests: [UInt64: CheckedContinuation<Data, Error>] = [:]
        /// The avatar data this device serves when asked -- set by the App layer
        /// from whatever the local profile's avatar currently is. `nil` means "no
        /// avatar," and a request for one simply gets no response.
        var localAvatarData: Data?
    }
    private let state = Locked(State())

    init(mySessionID: UInt64) {
        myPeerID = MCPeerID(displayName: "\(Self.peerIDPrefix)\(mySessionID)")
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func setLocalAvatarData(_ data: Data?) {
        state.withLock { $0.localAvatarData = data }
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    func requestAvatar(from peer: any PeerHandle) async throws -> Data {
        guard let handle = peer as? BLEPeerHandle else { throw BLEError.wrongPeerHandleType }
        let sessionID = handle.sessionID
        try await connectIfNeeded(sessionID)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let mcPeer = state.withLock { state -> MCPeerID? in
                guard let mcPeer = state.discoveredPeersBySessionID[sessionID] else { return nil }
                state.pendingAvatarRequests[sessionID] = continuation
                return mcPeer
            }
            guard let mcPeer else {
                continuation.resume(throwing: MultipeerError.peerNotFound)
                return
            }
            do {
                try session.send(
                    Data(MultipeerMessage.avatarRequest.rawValue.utf8), toPeers: [mcPeer], with: .reliable
                )
            } catch {
                let pending = state.withLock { $0.pendingAvatarRequests.removeValue(forKey: sessionID) }
                pending?.resume(throwing: error)
            }
        }
    }

    private func connectIfNeeded(_ sessionID: UInt64) async throws {
        let mcPeer = state.withLock { $0.discoveredPeersBySessionID[sessionID] }
        guard let mcPeer else { throw MultipeerError.peerNotFound }
        if session.connectedPeers.contains(mcPeer) { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.withLock { $0.pendingConnections[sessionID] = continuation }
            browser.invitePeer(mcPeer, to: session, withContext: nil, timeout: 15)
        }
    }

    fileprivate static func sessionID(from peerID: MCPeerID) -> UInt64? {
        guard peerID.displayName.hasPrefix(peerIDPrefix) else { return nil }
        return UInt64(peerID.displayName.dropFirst(peerIDPrefix.count))
    }
}

enum MultipeerError: Error {
    case peerNotFound
}

private enum MultipeerMessage: String {
    case avatarRequest = "AVATAR_REQUEST"
}

extension MultipeerAvatarTransport: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard let sessionID = Self.sessionID(from: peerID) else { return }
        state.withLock { $0.discoveredPeersBySessionID[sessionID] = peerID }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        guard let sessionID = Self.sessionID(from: peerID) else { return }
        state.withLock { $0.discoveredPeersBySessionID.removeValue(forKey: sessionID) }
    }
}

extension MultipeerAvatarTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // ROADMAP 3a's consent gate is the BLE two-stage disclosure, already
        // satisfied before this transport is ever asked to fetch anything --
        // accepting the Multipeer *session* itself isn't a second disclosure point,
        // just the transport connection underneath an already-consented exchange.
        invitationHandler(true, session)
    }
}

extension MultipeerAvatarTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard let sessionID = Self.sessionID(from: peerID) else { return }
        let continuation = self.state.withLock { $0.pendingConnections.removeValue(forKey: sessionID) }
        switch state {
        case .connected: continuation?.resume()
        case .notConnected: continuation?.resume(throwing: MultipeerError.peerNotFound)
        case .connecting: break
        @unknown default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let sessionID = Self.sessionID(from: peerID) else { return }

        if let message = String(data: data, encoding: .utf8), message == MultipeerMessage.avatarRequest.rawValue {
            let avatarData = state.withLock { $0.localAvatarData }
            if let avatarData {
                try? session.send(avatarData, toPeers: [peerID], with: .reliable)
            }
            return
        }

        let continuation = state.withLock { $0.pendingAvatarRequests.removeValue(forKey: sessionID) }
        continuation?.resume(returning: data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {}
    func session(
        _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?
    ) {}
}
