import Foundation
import Testing
@testable import ContrailDiscovery

struct HandshakeRecordTests {
    @Test func encodedRoundTripsThroughDecode() throws {
        let record = HandshakeRecord(displayName: "Tom", flightsLogged: 12, homeBaseICAO: "KDEN", avatarHash: "abc123")
        let decoded = try HandshakeRecord.decode(record.encoded())
        #expect(decoded == record)
    }

    @Test func nilAvatarHashRoundTrips() throws {
        let record = HandshakeRecord(displayName: "Sam", flightsLogged: 0, homeBaseICAO: nil, avatarHash: nil)
        let decoded = try HandshakeRecord.decode(record.encoded())
        #expect(decoded.avatarHash == nil)
    }
}

struct TwoStageDisclosureTests {
    @Test func startsAtPresenceOnly() {
        #expect(TwoStageDisclosure().state == .presenceOnly)
    }

    @Test func myRequestThenTheirsReachesMutual() {
        var disclosure = TwoStageDisclosure()
        #expect(disclosure.requestByMe() == .requestedByMe)
        #expect(disclosure.requestByThem() == .mutuallyAccepted)
        #expect(disclosure.canExchangeProfile)
    }

    @Test func theirRequestThenMineReachesMutual() {
        var disclosure = TwoStageDisclosure()
        #expect(disclosure.requestByThem() == .requestedByThem)
        #expect(disclosure.requestByMe() == .mutuallyAccepted)
        #expect(disclosure.canExchangeProfile)
    }

    @Test func repeatingMyOwnRequestDoesNotAdvanceAlone() {
        var disclosure = TwoStageDisclosure()
        disclosure.requestByMe()
        #expect(disclosure.requestByMe() == .requestedByMe)
        #expect(!disclosure.canExchangeProfile)
    }

    @Test func onceMutualFurtherRequestsAreNoOps() {
        var disclosure = TwoStageDisclosure()
        disclosure.requestByMe()
        disclosure.requestByThem()
        #expect(disclosure.requestByMe() == .mutuallyAccepted)
        #expect(disclosure.requestByThem() == .mutuallyAccepted)
    }
}
