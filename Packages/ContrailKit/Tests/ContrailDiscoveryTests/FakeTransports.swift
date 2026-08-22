import Foundation
@testable import ContrailDiscovery

final class FakePeerHandle: PeerHandle, Sendable {
    let id: UInt64
    init(id: UInt64) { self.id = id }
}

final class FakeAdvertiser: BeaconAdvertiser, @unchecked Sendable {
    private(set) var advertisedPayload: BeaconPayload?
    private(set) var isAdvertising = false

    func startAdvertising(_ payload: BeaconPayload) {
        advertisedPayload = payload
        isAdvertising = true
    }

    func stopAdvertising() {
        isAdvertising = false
    }
}

/// `simulateSighting` is `async` and calls the stored callback directly (no `Task`
/// hop) -- see `BeaconScanner`'s own doc comment for why that's what keeps engine
/// tests deterministic rather than timing-dependent.
final class FakeScanner: BeaconScanner, @unchecked Sendable {
    private var onSighting: (@Sendable (BeaconSighting) async -> Void)?
    private(set) var isScanning = false

    func startScanning(onSighting: @escaping @Sendable (BeaconSighting) async -> Void) {
        self.onSighting = onSighting
        isScanning = true
    }

    func stopScanning() {
        isScanning = false
        onSighting = nil
    }

    func simulateSighting(_ sighting: BeaconSighting) async {
        await onSighting?(sighting)
    }
}

enum FakeTransportError: Error {
    case noRecord
    case noAvatar
}

actor FakeHandshakeTransport: HandshakeTransport {
    private(set) var sentRequestIDs: [UInt64] = []
    private var recordsByPeerID: [UInt64: HandshakeRecord] = [:]

    func setRecord(_ record: HandshakeRecord, for peerID: UInt64) {
        recordsByPeerID[peerID] = record
    }

    func sendExchangeRequest(to peer: any PeerHandle) async throws {
        if let handle = peer as? FakePeerHandle {
            sentRequestIDs.append(handle.id)
        }
    }

    func readHandshakeRecord(from peer: any PeerHandle) async throws -> HandshakeRecord {
        guard let handle = peer as? FakePeerHandle, let record = recordsByPeerID[handle.id] else {
            throw FakeTransportError.noRecord
        }
        return record
    }
}

actor FakeBulkTransferTransport: BulkTransferTransport {
    private(set) var requestCount = 0
    private var avatarsByPeerID: [UInt64: Data] = [:]

    func setAvatar(_ data: Data, for peerID: UInt64) {
        avatarsByPeerID[peerID] = data
    }

    func requestAvatar(from peer: any PeerHandle) async throws -> Data {
        requestCount += 1
        guard let handle = peer as? FakePeerHandle, let data = avatarsByPeerID[handle.id] else {
            throw FakeTransportError.noAvatar
        }
        return data
    }
}
