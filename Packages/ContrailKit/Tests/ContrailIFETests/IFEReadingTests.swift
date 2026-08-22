import Foundation
import Testing
import ContrailCore
@testable import ContrailIFE

struct IFEReadingTests {
    @Test func emptyReadingReportsEmpty() {
        #expect(IFEReading().isEmpty)
    }

    @Test func nonEmptyReadingReportsNotEmpty() {
        #expect(!IFEReading(staticAirTemperatureC: -55).isEmpty)
        #expect(!IFEReading(groundspeedMS: 240).isEmpty)
    }

    @Test func asOutsideAirDataPromotesOnlyTemperatureTASWindFieldsAsIFESourced() {
        let reading = IFEReading(
            staticAirTemperatureC: -56.5, trueAirspeedMS: 245, windSpeedMS: 12, windDirectionDeg: 270,
            groundspeedMS: 230, latitude: 39.0, longitude: -104.0, timeToDestinationSeconds: 3600
        )
        let outsideAir = reading.asOutsideAirData()

        #expect(outsideAir.staticAirTemperature.value == -56.5)
        #expect(outsideAir.staticAirTemperature.source == .ife)
        #expect(outsideAir.trueAirspeed.value == 245)
        #expect(outsideAir.windSpeed.value == 12)
        #expect(outsideAir.windDirection.value == 270)
    }

    @Test func asOutsideAirDataLeavesMissingFieldsUnavailableNotZero() {
        let reading = IFEReading(staticAirTemperatureC: -56.5)
        let outsideAir = reading.asOutsideAirData()

        #expect(outsideAir.trueAirspeed.value == nil)
        #expect(outsideAir.trueAirspeed.source == .unavailable)
        #expect(outsideAir.windSpeed.source == .unavailable)
        #expect(outsideAir.windDirection.source == .unavailable)
    }
}
