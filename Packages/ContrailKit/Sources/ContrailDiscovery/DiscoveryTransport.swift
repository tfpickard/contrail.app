import Foundation

/// An opaque reference to a specific nearby peer, as whatever platform transport
/// discovered it (a `CBPeripheral` wrapper for BLE, an `MCPeerID` wrapper for
/// MultipeerConnectivity). `PassengerDiscoveryEngine` never inspects the concrete
/// type -- it just holds one per `DiscoveredPeer` and hands it back to whichever
/// transport method needs to address that peer. Real conformers live in the App
/// layer, next to the CoreBluetooth/MultipeerConnectivity code that produces them;
/// this package only needs the marker.
public protocol PeerHandle: Sendable {}

public struct BeaconSighting: Sendable {
    public let peer: any PeerHandle
    public let payload: BeaconPayload
    public let rssi: Int?

    public init(peer: any PeerHandle, payload: BeaconPayload, rssi: Int?) {
        self.peer = peer
        self.payload = payload
        self.rssi = rssi
    }
}

/// ROADMAP 3a: "BLE as the beacon." Advertises this device's own presence-only
/// payload. A real conformer wraps `CBPeripheralManager`.
public protocol BeaconAdvertiser: Sendable {
    func startAdvertising(_ payload: BeaconPayload)
    func stopAdvertising()
}

/// The scanning half -- finds other devices advertising the same service. A real
/// conformer wraps `CBCentralManager`; since `CBCentralManagerDelegate` callbacks
/// aren't themselves `async`, that conformer is responsible for bridging into an
/// unstructured `Task` internally. `onSighting` being `async` here is what lets
/// `PassengerDiscoveryEngine.start()` await each sighting directly instead of
/// spawning its own `Task` per callback -- and it's what makes a fake scanner's
/// `simulateSighting` in tests deterministic, with no sleep-and-hope needed.
public protocol BeaconScanner: Sendable {
    func startScanning(onSighting: @escaping @Sendable (BeaconSighting) async -> Void)
    func stopScanning()
}

/// ROADMAP 3a: "GATT for the handshake." `sendExchangeRequest` is stage one of the
/// two-stage disclosure -- it tells the *remote* device I'd like to exchange
/// profiles, which is what lets their engine call `receiveExchangeRequest` in
/// response. `readHandshakeRecord` only ever gets called once both sides have
/// accepted (`PassengerDiscoveryEngine` enforces this, not the transport).
public protocol HandshakeTransport: Sendable {
    func sendExchangeRequest(to peer: any PeerHandle) async throws
    func readHandshakeRecord(from peer: any PeerHandle) async throws -> HandshakeRecord
}

/// ROADMAP 3a: "bulk transfer over peer-to-peer Wi-Fi... BLE's throughput is
/// measured in tens of kilobytes per second and is not the right pipe for images."
/// A real conformer wraps `MCSession`.
public protocol BulkTransferTransport: Sendable {
    func requestAvatar(from peer: any PeerHandle) async throws -> Data
}
