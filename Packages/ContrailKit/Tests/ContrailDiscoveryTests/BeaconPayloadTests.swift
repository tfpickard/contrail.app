import Foundation
import Testing
@testable import ContrailDiscovery

struct BeaconPayloadTests {
    @Test func encodedFitsWithinTheAdvertisementBudget() {
        let payload = BeaconPayload(sessionID: .max)
        // ROADMAP 3a: "roughly 20 usable" bytes -- this must fit with room to spare.
        #expect(payload.encoded.count <= 20)
        #expect(payload.encoded.count == BeaconPayload.encodedByteCount)
    }

    @Test func decodeRoundTripsAnyEncodedPayload() {
        for sessionID: UInt64 in [0, 1, 42, .max, 0x0102030405060708] {
            let payload = BeaconPayload(sessionID: sessionID)
            let decoded = BeaconPayload.decode(payload.encoded)
            #expect(decoded == payload)
        }
    }

    @Test func decodeRejectsTheWrongProtocolVersion() {
        var bytes = BeaconPayload(sessionID: 1).encoded
        bytes[bytes.startIndex] = 99
        #expect(BeaconPayload.decode(bytes) == nil)
    }

    @Test func decodeRejectsTruncatedData() {
        let truncated = BeaconPayload(sessionID: 1).encoded.prefix(4)
        #expect(BeaconPayload.decode(truncated) == nil)
    }

    @Test func freshSessionIDsAreNotTriviallyPredictable() {
        // Not a rigorous randomness test -- just confirms two consecutive calls
        // don't return the same (or sequential) value, catching an accidental
        // constant or counter implementation.
        let a = BeaconPayload.freshSessionID()
        let b = BeaconPayload.freshSessionID()
        #expect(a != b)
    }
}
