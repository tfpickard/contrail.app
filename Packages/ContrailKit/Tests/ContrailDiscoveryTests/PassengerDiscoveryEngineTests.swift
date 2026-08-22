import Foundation
import Testing
@testable import ContrailDiscovery

private func makeEngine(
    advertiser: FakeAdvertiser = FakeAdvertiser(),
    scanner: FakeScanner = FakeScanner(),
    handshake: FakeHandshakeTransport = FakeHandshakeTransport(),
    bulk: FakeBulkTransferTransport = FakeBulkTransferTransport()
) -> PassengerDiscoveryEngine {
    PassengerDiscoveryEngine(
        advertiser: advertiser, scanner: scanner,
        handshakeTransport: handshake, bulkTransport: bulk,
        myPayload: BeaconPayload(sessionID: 1)
    )
}

struct PassengerDiscoveryEngineTests {
    @Test func startBeginsAdvertisingAndScanning() async {
        let advertiser = FakeAdvertiser()
        let scanner = FakeScanner()
        let engine = makeEngine(advertiser: advertiser, scanner: scanner)

        await engine.start()

        #expect(advertiser.isAdvertising)
        #expect(scanner.isScanning)
    }

    @Test func stopEndsBothAdvertisingAndScanning() async {
        let advertiser = FakeAdvertiser()
        let scanner = FakeScanner()
        let engine = makeEngine(advertiser: advertiser, scanner: scanner)

        await engine.start()
        await engine.stop()

        #expect(!advertiser.isAdvertising)
        #expect(!scanner.isScanning)
    }

    @Test func sightingAppearsInDiscoveredPeersAsPresenceOnly() async {
        let scanner = FakeScanner()
        let engine = makeEngine(scanner: scanner)
        await engine.start()

        await scanner.simulateSighting(
            BeaconSighting(peer: FakePeerHandle(id: 42), payload: BeaconPayload(sessionID: 42), rssi: -60)
        )

        let peers = await engine.discoveredPeers
        #expect(peers.count == 1)
        #expect(peers.first?.id == 42)
        #expect(peers.first?.disclosure == .presenceOnly)
        #expect(peers.first?.handshakeRecord == nil)
    }

    @Test func myRequestThenTheirAcceptanceFetchesTheHandshakeRecord() async throws {
        let scanner = FakeScanner()
        let handshake = FakeHandshakeTransport()
        let engine = makeEngine(scanner: scanner, handshake: handshake)
        await engine.start()

        await scanner.simulateSighting(
            BeaconSighting(peer: FakePeerHandle(id: 7), payload: BeaconPayload(sessionID: 7), rssi: nil)
        )
        let record = HandshakeRecord(displayName: "Sam", flightsLogged: 3, homeBaseICAO: "KJFK", avatarHash: "abc")
        await handshake.setRecord(record, for: 7)

        try await engine.requestProfileExchange(with: 7)
        var peer = await engine.discoveredPeers.first
        #expect(peer?.disclosure == .requestedByMe)
        #expect(peer?.handshakeRecord == nil)
        #expect(await handshake.sentRequestIDs == [7])

        try await engine.receiveExchangeRequest(from: 7)
        peer = await engine.discoveredPeers.first
        #expect(peer?.disclosure == .mutuallyAccepted)
        #expect(peer?.handshakeRecord == record)
    }

    @Test func theirRequestThenMyAcceptanceAlsoFetchesTheRecord() async throws {
        let scanner = FakeScanner()
        let handshake = FakeHandshakeTransport()
        let engine = makeEngine(scanner: scanner, handshake: handshake)
        await engine.start()

        await scanner.simulateSighting(
            BeaconSighting(peer: FakePeerHandle(id: 8), payload: BeaconPayload(sessionID: 8), rssi: nil)
        )
        let record = HandshakeRecord(displayName: "Alex", flightsLogged: 0, homeBaseICAO: nil, avatarHash: nil)
        await handshake.setRecord(record, for: 8)

        try await engine.receiveExchangeRequest(from: 8)
        var peer = await engine.discoveredPeers.first
        #expect(peer?.disclosure == .requestedByThem)

        try await engine.requestProfileExchange(with: 8)
        peer = await engine.discoveredPeers.first
        #expect(peer?.disclosure == .mutuallyAccepted)
        #expect(peer?.handshakeRecord == record)
    }

    @Test func avatarIsFetchedOnceThenServedFromCache() async throws {
        let scanner = FakeScanner()
        let handshake = FakeHandshakeTransport()
        let bulk = FakeBulkTransferTransport()
        let engine = makeEngine(scanner: scanner, handshake: handshake, bulk: bulk)
        await engine.start()

        await scanner.simulateSighting(
            BeaconSighting(peer: FakePeerHandle(id: 9), payload: BeaconPayload(sessionID: 9), rssi: nil)
        )
        await handshake.setRecord(
            HandshakeRecord(displayName: "Alex", flightsLogged: 1, homeBaseICAO: nil, avatarHash: "hash-9"),
            for: 9
        )
        try await engine.requestProfileExchange(with: 9)
        try await engine.receiveExchangeRequest(from: 9)

        let avatarData = Data([1, 2, 3])
        await bulk.setAvatar(avatarData, for: 9)

        let first = try await engine.fetchAvatar(for: 9)
        #expect(first == avatarData)
        #expect(await bulk.requestCount == 1)

        let second = try await engine.fetchAvatar(for: 9)
        #expect(second == avatarData)
        // Cached -- the transport is not asked again.
        #expect(await bulk.requestCount == 1)
    }

    @Test func fetchAvatarReturnsNilWhenThePeerHasNoAvatarSet() async throws {
        let scanner = FakeScanner()
        let handshake = FakeHandshakeTransport()
        let engine = makeEngine(scanner: scanner, handshake: handshake)
        await engine.start()

        await scanner.simulateSighting(
            BeaconSighting(peer: FakePeerHandle(id: 5), payload: BeaconPayload(sessionID: 5), rssi: nil)
        )
        await handshake.setRecord(
            HandshakeRecord(displayName: "NoAvatar", flightsLogged: 0, homeBaseICAO: nil, avatarHash: nil),
            for: 5
        )
        try await engine.requestProfileExchange(with: 5)
        try await engine.receiveExchangeRequest(from: 5)

        let result = try await engine.fetchAvatar(for: 5)
        #expect(result == nil)
    }

    @Test func fetchAvatarReturnsNilBeforeDisclosureIsMutual() async throws {
        let scanner = FakeScanner()
        let engine = makeEngine(scanner: scanner)
        await engine.start()

        await scanner.simulateSighting(
            BeaconSighting(peer: FakePeerHandle(id: 3), payload: BeaconPayload(sessionID: 3), rssi: nil)
        )

        let result = try await engine.fetchAvatar(for: 3)
        #expect(result == nil)
    }
}
