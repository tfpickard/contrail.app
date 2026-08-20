import Testing
@testable import ContrailCore

struct ISAAtmosphereTests {
    @Test func seaLevelPressureIsStandard() {
        let pressure = ISAAtmosphere.pressureKPa(altitude: 0)
        #expect(abs(pressure - 101.325) < 0.001)
    }

    @Test func pressureDecreasesWithAltitude() {
        let low = ISAAtmosphere.pressureKPa(altitude: 0)
        let high = ISAAtmosphere.pressureKPa(altitude: 10_000)
        #expect(high < low)
    }

    @Test func inverseRoundTripsForCruiseAltitudes() {
        for altitude in stride(from: 0.0, through: 12_000, by: 1_000) {
            let pressure = ISAAtmosphere.pressureKPa(altitude: altitude)
            let recovered = ISAAtmosphere.altitude(pressureKPa: pressure)
            #expect(abs(recovered - altitude) < 0.01, "mismatch at \(altitude)m")
        }
    }

    @Test func cabinAltitudeAroundEightThousandFeetGivesPlausiblePressure() {
        // A typical airliner cabin altitude, ~2438 m (8000 ft), should read close to
        // 75.3 kPa -- the commonly cited figure for that altitude.
        let pressure = ISAAtmosphere.pressureKPa(altitude: 2438)
        #expect(abs(pressure - 75.3) < 0.5)
    }
}
