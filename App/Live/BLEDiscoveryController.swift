import Foundation
import CoreBluetooth
import ContrailDiscovery

/// The project's own BLE service. Generated once for Contrail, never to be reused
/// for anything else.
///
/// **Verification limit, stated plainly**: CoreBluetooth has no Simulator support
/// at all -- `CBCentralManager`/`CBPeripheralManager` both report `.unsupported` in
/// the iOS Simulator, and this build environment has no physical device pair to
/// test real two-phone discovery against. Every method here is verified for API
/// correctness (matches documented `CoreBluetooth` semantics, compiles against the
/// real SDK) but the actual advertise-scan-connect-handshake sequence between two
/// real Contrail installs has not been exercised end-to-end. `ContrailDiscovery`'s
/// own test suite covers the orchestration logic this class feeds
/// (`PassengerDiscoveryEngine`) with fake transports precisely because that logic
/// -- unlike this file -- doesn't require hardware to verify.
enum ContrailBLE {
    // `CBUUID` is an immutable value wrapper in practice but isn't audited
    // `Sendable` by Apple, which is what triggers Swift 6's warning on a plain
    // `static let` here -- `nonisolated(unsafe)` is the documented escape hatch
    // for exactly this "genuinely safe, not yet audited" case.
    nonisolated(unsafe) static let serviceUUID = CBUUID(string: "7C9D6F2E-8A1B-4C3D-9E5F-0A1B2C3D4E5F")
    nonisolated(unsafe) static let handshakeRecordCharacteristicUUID = CBUUID(string: "7C9D6F2E-8A1B-4C3D-9E5F-0A1B2C3D4E60")
    nonisolated(unsafe) static let exchangeRequestCharacteristicUUID = CBUUID(string: "7C9D6F2E-8A1B-4C3D-9E5F-0A1B2C3D4E61")
}

enum BLEError: Error {
    case wrongPeerHandleType
    case serviceNotFound
    case characteristicNotFound
    case connectFailed
    case malformedRecord
}

final class BLEPeerHandle: PeerHandle, @unchecked Sendable {
    let peripheral: CBPeripheral
    /// Carried alongside the peripheral so `MultipeerAvatarTransport` -- a
    /// completely separate framework with no notion of `CBPeripheral` -- can
    /// correlate "the peer BLE found" with "the peer Multipeer found" via the one
    /// number both sides agree on. See that type's own doc comment.
    let sessionID: UInt64

    init(peripheral: CBPeripheral, sessionID: UInt64) {
        self.peripheral = peripheral
        self.sessionID = sessionID
    }
}

/// One class, both BLE roles at once -- ROADMAP 3a's beacon-advertise and GATT-
/// handshake both happen over BLE, and a single physical device plays both central
/// (scanning for others) and peripheral (being found by others) simultaneously,
/// which is exactly what `CBCentralManager` + `CBPeripheralManager` in one object
/// gives us. `MultipeerAvatarTransport` is the separate Wi-Fi half.
final class BLEDiscoveryController: NSObject, BeaconAdvertiser, BeaconScanner, HandshakeTransport, @unchecked Sendable {
    private let peripheralManager: CBPeripheralManager
    private let centralManager: CBCentralManager

    private struct State {
        var handshakeCharacteristic: CBMutableCharacteristic?
        var exchangeRequestCharacteristic: CBMutableCharacteristic?
        var currentRecordData = Data()
        var pendingAdvertisePayload: BeaconPayload?
        var myOwnSessionID: UInt64?
        var onSighting: (@Sendable (BeaconSighting) async -> Void)?
        var connections: [UUID: CheckedContinuation<Void, Error>] = [:]
        var serviceDiscoveries: [UUID: CheckedContinuation<Void, Error>] = [:]
        var characteristicDiscoveries: [UUID: CheckedContinuation<Void, Error>] = [:]
        var pendingReads: [UUID: CheckedContinuation<HandshakeRecord, Error>] = [:]
        var pendingWrites: [UUID: CheckedContinuation<Void, Error>] = [:]
    }
    private let state = Locked(State())

    /// Wired by the App layer to the local `PassengerDiscoveryEngine`'s
    /// `receiveExchangeRequest(from:)`. Fires when a remote central writes an
    /// exchange request to us -- the local side of ROADMAP 3a's two-stage
    /// disclosure the *other* device initiated.
    var onExchangeRequestReceived: (@Sendable (UInt64) -> Void)?

    override init() {
        peripheralManager = CBPeripheralManager(delegate: nil, queue: nil)
        centralManager = CBCentralManager(delegate: nil, queue: nil)
        super.init()
        peripheralManager.delegate = self
        centralManager.delegate = self
    }

    /// Call whenever the local profile changes -- the next GATT read reflects it
    /// immediately, no re-advertise required.
    func updateLocalRecord(_ record: HandshakeRecord) {
        let data = (try? record.encoded()) ?? Data()
        state.withLock { $0.currentRecordData = data }
    }

    // MARK: - BeaconAdvertiser

    func startAdvertising(_ payload: BeaconPayload) {
        let ready = state.withLock { state -> Bool in
            state.pendingAdvertisePayload = payload
            state.myOwnSessionID = payload.sessionID
            return self.peripheralManager.state == .poweredOn
        }
        if ready { beginAdvertising(payload) }
    }

    func stopAdvertising() {
        state.withLock { $0.pendingAdvertisePayload = nil }
        peripheralManager.stopAdvertising()
    }

    private func beginAdvertising(_ payload: BeaconPayload) {
        let needsService = state.withLock { $0.handshakeCharacteristic == nil }

        if needsService {
            let handshake = CBMutableCharacteristic(
                type: ContrailBLE.handshakeRecordCharacteristicUUID, properties: [.read],
                value: nil, permissions: [.readable]
            )
            let exchangeRequest = CBMutableCharacteristic(
                type: ContrailBLE.exchangeRequestCharacteristicUUID, properties: [.write],
                value: nil, permissions: [.writeable]
            )
            let service = CBMutableService(type: ContrailBLE.serviceUUID, primary: true)
            service.characteristics = [handshake, exchangeRequest]

            state.withLock {
                $0.handshakeCharacteristic = handshake
                $0.exchangeRequestCharacteristic = exchangeRequest
            }

            peripheralManager.add(service)
        }

        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [ContrailBLE.serviceUUID],
            CBAdvertisementDataServiceDataKey: [ContrailBLE.serviceUUID: payload.encoded],
        ])
    }

    // MARK: - BeaconScanner

    func startScanning(onSighting: @escaping @Sendable (BeaconSighting) async -> Void) {
        let ready = state.withLock { state -> Bool in
            state.onSighting = onSighting
            return self.centralManager.state == .poweredOn
        }
        if ready {
            centralManager.scanForPeripherals(
                withServices: [ContrailBLE.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func stopScanning() {
        state.withLock { $0.onSighting = nil }
        centralManager.stopScan()
    }

    // MARK: - HandshakeTransport

    func sendExchangeRequest(to peer: any PeerHandle) async throws {
        guard let handle = peer as? BLEPeerHandle else { throw BLEError.wrongPeerHandleType }
        try await connectAndDiscover(handle.peripheral)

        guard let characteristic = exchangeRequestCharacteristic(on: handle.peripheral) else {
            throw BLEError.characteristicNotFound
        }
        guard let sessionID = state.withLock({ $0.myOwnSessionID }) else { throw BLEError.connectFailed }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.withLock { $0.pendingWrites[handle.peripheral.identifier] = continuation }
            handle.peripheral.writeValue(BeaconPayload(sessionID: sessionID).encoded, for: characteristic, type: .withResponse)
        }
    }

    func readHandshakeRecord(from peer: any PeerHandle) async throws -> HandshakeRecord {
        guard let handle = peer as? BLEPeerHandle else { throw BLEError.wrongPeerHandleType }
        try await connectAndDiscover(handle.peripheral)

        guard let characteristic = handshakeCharacteristic(on: handle.peripheral) else {
            throw BLEError.characteristicNotFound
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HandshakeRecord, Error>) in
            state.withLock { $0.pendingReads[handle.peripheral.identifier] = continuation }
            handle.peripheral.readValue(for: characteristic)
        }
    }

    private func handshakeCharacteristic(on peripheral: CBPeripheral) -> CBCharacteristic? {
        peripheral.services?.first(where: { $0.uuid == ContrailBLE.serviceUUID })?
            .characteristics?.first(where: { $0.uuid == ContrailBLE.handshakeRecordCharacteristicUUID })
    }

    private func exchangeRequestCharacteristic(on peripheral: CBPeripheral) -> CBCharacteristic? {
        peripheral.services?.first(where: { $0.uuid == ContrailBLE.serviceUUID })?
            .characteristics?.first(where: { $0.uuid == ContrailBLE.exchangeRequestCharacteristicUUID })
    }

    private func connectAndDiscover(_ peripheral: CBPeripheral) async throws {
        if peripheral.state != .connected {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                state.withLock { $0.connections[peripheral.identifier] = continuation }
                peripheral.delegate = self
                centralManager.connect(peripheral, options: nil)
            }
        }
        if handshakeCharacteristic(on: peripheral) != nil { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.withLock { $0.serviceDiscoveries[peripheral.identifier] = continuation }
            peripheral.discoverServices([ContrailBLE.serviceUUID])
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == ContrailBLE.serviceUUID }) else {
            throw BLEError.serviceNotFound
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            state.withLock { $0.characteristicDiscoveries[peripheral.identifier] = continuation }
            peripheral.discoverCharacteristics(
                [ContrailBLE.handshakeRecordCharacteristicUUID, ContrailBLE.exchangeRequestCharacteristicUUID],
                for: service
            )
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEDiscoveryController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let shouldScan = state.withLock { central.state == .poweredOn && $0.onSighting != nil }
        if shouldScan {
            central.scanForPeripherals(
                withServices: [ContrailBLE.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let payloadData = serviceData[ContrailBLE.serviceUUID],
              let payload = BeaconPayload.decode(payloadData) else { return }

        guard let callback = state.withLock({ $0.onSighting }) else { return }

        let sighting = BeaconSighting(
            peer: BLEPeerHandle(peripheral: peripheral, sessionID: payload.sessionID),
            payload: payload, rssi: RSSI.intValue
        )
        Task { await callback(sighting) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let continuation = state.withLock { $0.connections.removeValue(forKey: peripheral.identifier) }
        continuation?.resume()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let continuation = state.withLock { $0.connections.removeValue(forKey: peripheral.identifier) }
        continuation?.resume(throwing: error ?? BLEError.connectFailed)
    }
}

// MARK: - CBPeripheralDelegate

extension BLEDiscoveryController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let continuation = state.withLock { $0.serviceDiscoveries.removeValue(forKey: peripheral.identifier) }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let continuation = state.withLock { $0.characteristicDiscoveries.removeValue(forKey: peripheral.identifier) }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let continuation = state.withLock({ $0.pendingReads.removeValue(forKey: peripheral.identifier) }) else { return }
        if let error {
            continuation.resume(throwing: error)
            return
        }
        guard let data = characteristic.value, let record = try? HandshakeRecord.decode(data) else {
            continuation.resume(throwing: BLEError.malformedRecord)
            return
        }
        continuation.resume(returning: record)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let continuation = state.withLock { $0.pendingWrites.removeValue(forKey: peripheral.identifier) }
        if let error { continuation?.resume(throwing: error) } else { continuation?.resume() }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEDiscoveryController: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let payload = state.withLock { peripheral.state == .poweredOn ? $0.pendingAdvertisePayload : nil }
        if let payload { beginAdvertising(payload) }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == ContrailBLE.handshakeRecordCharacteristicUUID else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        let data = state.withLock { $0.currentRecordData }
        guard request.offset <= data.count else {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = data.subdata(in: request.offset..<data.count)
        peripheral.respond(to: request, withResult: .success)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests where request.characteristic.uuid == ContrailBLE.exchangeRequestCharacteristicUUID {
            if let value = request.value, let payload = BeaconPayload.decode(value) {
                onExchangeRequestReceived?(payload.sessionID)
            }
        }
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }
}
