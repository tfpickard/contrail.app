import Foundation
import Testing
@testable import ContrailCore

struct OutsideAirDataTests {
    @Test func unavailableHasEveryChannelUnavailable() {
        let data = OutsideAirData.unavailable
        #expect(data.staticAirTemperature.source == .unavailable)
        #expect(data.trueAirspeed.source == .unavailable)
        #expect(data.windSpeed.source == .unavailable)
        #expect(data.windDirection.source == .unavailable)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = OutsideAirData(
            staticAirTemperature: Channel(value: -56.5, source: .ife),
            trueAirspeed: Channel(value: 245.0, source: .ife),
            windSpeed: .unavailable,
            windDirection: .unavailable
        )
        let encoded = try JSONEncoder().encode(data)
        let decoded = try JSONDecoder().decode(OutsideAirData.self, from: encoded)
        #expect(decoded == data)
    }
}
