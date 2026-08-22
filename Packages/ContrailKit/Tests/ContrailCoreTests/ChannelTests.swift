import Foundation
import Testing
@testable import ContrailCore

struct ChannelTests {
    @Test func unavailableChannelHasNoValueAndUnavailableSource() {
        let channel: Channel<Double> = .unavailable
        #expect(channel.value == nil)
        #expect(channel.source == .unavailable)
        #expect(channel.age == nil)
    }

    @Test func presentValueRoundTripsThroughJSON() throws {
        let channel = Channel(value: 42.0, source: .gnss, age: 0.4)
        let data = try JSONEncoder().encode(channel)
        let decoded = try JSONDecoder().decode(Channel<Double>.self, from: data)
        #expect(decoded == channel)
    }

    @Test func unavailableChannelRoundTripsThroughJSONAsNull() throws {
        let channel: Channel<Double> = .unavailable
        let data = try JSONEncoder().encode(channel)

        // Structural check via JSONSerialization rather than string-matching the
        // encoder's exact spacing/key-ordering, which is an implementation detail.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?.keys.contains("value") == true)
        #expect(object?["value"] is NSNull)

        let decoded = try JSONDecoder().decode(Channel<Double>.self, from: data)
        #expect(decoded.value == nil)
        #expect(decoded.source == .unavailable)
    }

    @Test func schemaVersionCurrentIsMajorOne() {
        // Minor bumps with every additive schema change (most recently {1,1} for
        // Phase 3b's `outsideAir`) -- major is the number that actually matters to
        // pin here, since only a major bump means an old log line stops parsing.
        #expect(SchemaVersion.current.major == 1)
    }
}
