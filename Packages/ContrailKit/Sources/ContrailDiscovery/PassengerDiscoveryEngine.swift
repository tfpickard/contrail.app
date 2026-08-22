import Foundation

/// ROADMAP 3a's whole passenger-discovery feature, transport-agnostic. Real
/// CoreBluetooth/MultipeerConnectivity conformers of `BeaconAdvertiser`/
/// `BeaconScanner`/`HandshakeTransport`/`BulkTransferTransport` live in the App
/// layer and get injected here -- exactly the `nearestPlace`/`forecastLookup`
/// injection pattern `ContrailEstimator` already uses, for the same reason: this
/// engine is fully testable with fake transports and knows nothing about Bluetooth
/// hardware or Wi-Fi.
///
/// An actor, not `@MainActor` -- sightings can arrive from a background scanning
/// callback at any time, and nothing here needs the main thread.
public actor PassengerDiscoveryEngine {
    private let advertiser: any BeaconAdvertiser
    private let scanner: any BeaconScanner
    private let handshakeTransport: any HandshakeTransport
    private let bulkTransport: any BulkTransferTransport
    private let avatarCache: any AvatarCache
    private let myPayload: BeaconPayload

    private var peers: [UInt64: DiscoveredPeer] = [:]
    private var handles: [UInt64: any PeerHandle] = [:]
    private var disclosures: [UInt64: TwoStageDisclosure] = [:]

    public init(
        advertiser: any BeaconAdvertiser,
        scanner: any BeaconScanner,
        handshakeTransport: any HandshakeTransport,
        bulkTransport: any BulkTransferTransport,
        avatarCache: any AvatarCache = InMemoryAvatarCache(),
        myPayload: BeaconPayload = BeaconPayload(sessionID: BeaconPayload.freshSessionID())
    ) {
        self.advertiser = advertiser
        self.scanner = scanner
        self.handshakeTransport = handshakeTransport
        self.bulkTransport = bulkTransport
        self.avatarCache = avatarCache
        self.myPayload = myPayload
    }

    /// ROADMAP 3a: "entirely opt-in and user-initiated. A dedicated screen the user
    /// deliberately opens." Nothing in this engine starts advertising or scanning
    /// on its own -- the App layer calls this only from that screen's `onAppear`.
    public func start() {
        advertiser.startAdvertising(myPayload)
        scanner.startScanning { [weak self] sighting in
            await self?.recordSighting(sighting)
        }
    }

    public func stop() {
        advertiser.stopAdvertising()
        scanner.stopScanning()
    }

    public var discoveredPeers: [DiscoveredPeer] {
        peers.values.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func recordSighting(_ sighting: BeaconSighting) {
        let id = sighting.payload.sessionID
        handles[id] = sighting.peer
        var peer = peers[id] ?? DiscoveredPeer(id: id, lastSeen: Date())
        peer.lastSeen = Date()
        peer.rssi = sighting.rssi
        peers[id] = peer
    }

    /// The user taps "exchange profiles" for a specific peer. Sends the request
    /// over BLE regardless of the resulting state (the remote side needs to hear
    /// about it even if -- rare, a race -- they'd already requested us first and
    /// this call is what flips us to `.mutuallyAccepted`).
    public func requestProfileExchange(with peerID: UInt64) async throws {
        guard let handle = handles[peerID] else { return }
        var disclosure = disclosures[peerID] ?? TwoStageDisclosure()
        let newState = disclosure.requestByMe()
        disclosures[peerID] = disclosure
        peers[peerID]?.disclosure = newState

        try await handshakeTransport.sendExchangeRequest(to: handle)

        if newState == .mutuallyAccepted {
            try await performExchange(with: peerID, handle: handle)
        }
    }

    /// Called by the App layer's `HandshakeTransport` conformer when it observes
    /// the peer at `peerID` asking *us* to exchange profiles (e.g. a GATT
    /// characteristic-write). Never called directly by UI code.
    public func receiveExchangeRequest(from peerID: UInt64) async throws {
        guard let handle = handles[peerID] else { return }
        var disclosure = disclosures[peerID] ?? TwoStageDisclosure()
        let newState = disclosure.requestByThem()
        disclosures[peerID] = disclosure
        peers[peerID]?.disclosure = newState

        if newState == .mutuallyAccepted {
            try await performExchange(with: peerID, handle: handle)
        }
    }

    private func performExchange(with peerID: UInt64, handle: any PeerHandle) async throws {
        let record = try await handshakeTransport.readHandshakeRecord(from: handle)
        peers[peerID]?.handshakeRecord = record
    }

    /// ROADMAP 3a: "avatar transfers only on explicit request, and the hash means a
    /// given person's image is fetched exactly once, ever." Returns `nil` (not an
    /// error) if disclosure isn't mutual yet or the peer has no avatar set -- both
    /// are ordinary states, not failures.
    public func fetchAvatar(for peerID: UInt64) async throws -> Data? {
        guard let handle = handles[peerID],
              let record = peers[peerID]?.handshakeRecord,
              let hash = record.avatarHash else { return nil }

        if let cached = avatarCache.data(forHash: hash) {
            peers[peerID]?.avatarData = cached
            return cached
        }

        let data = try await bulkTransport.requestAvatar(from: handle)
        avatarCache.store(data, forHash: hash)
        peers[peerID]?.avatarData = data
        return data
    }
}
