import Foundation
import Testing
import ContrailCore
import ContrailGeo
@testable import ContrailSensors

struct SyntheticFlightLogTests {
    private let den = Coordinate(latitude: 39.8617, longitude: -104.6731)
    private let lax = Coordinate(latitude: 33.9416, longitude: -118.4085)
    private let departure = Date(timeIntervalSince1970: 1_755_639_600)

    @Test func finalLocationSampleIsCloseToDestination() throws {
        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        config.motionSampleInterval = 5
        config.pressureSampleInterval = 5

        let samples = try SyntheticFlightLog.generate(config)
        let locations = samples.compactMap { sample -> LocationSample? in
            if case .location(let s) = sample { return s }
            return nil
        }
        #expect(!locations.isEmpty)

        let final = locations.last!
        let distanceFromDestination = try VincentyGeodesic.inverse(from: final.coordinate, to: lax).distance
        // Within a couple of km — the rhumb-line approximation plus the final
        // location sample landing slightly before the very last instant.
        #expect(distanceFromDestination < 5_000)
    }

    @Test func altitudeProfileClimbsCruisesAndDescends() throws {
        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 10
        config.motionSampleInterval = 10
        config.pressureSampleInterval = 10

        let samples = try SyntheticFlightLog.generate(config)
        let altitudes = samples.compactMap { sample -> (Date, Double)? in
            if case .location(let s) = sample { return (s.timestamp, s.altitude) }
            return nil
        }

        let maxAltitude = altitudes.map(\.1).max()!
        #expect(maxAltitude > 10_000) // reaches cruise altitude

        let first = altitudes.first!.1
        let last = altitudes.last!.1
        #expect(first < 2000) // starts near ground elevation
        #expect(last < 2000)  // ends near ground elevation
    }

    @Test func gpsDropoutWindowHasNoLocationSamplesButKeepsMotionAndPressure() throws {
        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 1
        config.motionSampleInterval = 1
        config.pressureSampleInterval = 1
        // A 6-minute dropout during cruise, comfortably inside the flight.
        config.gpsDropout = (start: 40 * 60, duration: 6 * 60)

        let samples = try SyntheticFlightLog.generate(config)
        let dropoutStart = departure.addingTimeInterval(40 * 60)
        let dropoutEnd = departure.addingTimeInterval(46 * 60)

        let locationsDuringDropout = samples.filter { sample in
            guard case .location = sample else { return false }
            return sample.timestamp >= dropoutStart && sample.timestamp < dropoutEnd
        }
        #expect(locationsDuringDropout.isEmpty)

        let motionDuringDropout = samples.filter { sample in
            guard case .motion = sample else { return false }
            return sample.timestamp >= dropoutStart && sample.timestamp < dropoutEnd
        }
        #expect(!motionDuringDropout.isEmpty)

        let pressureDuringDropout = samples.filter { sample in
            guard case .pressure = sample else { return false }
            return sample.timestamp >= dropoutStart && sample.timestamp < dropoutEnd
        }
        #expect(!pressureDuringDropout.isEmpty)
    }

    @Test func groundspeedIsZeroDuringTaxiAndPositiveAtCruise() throws {
        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 2
        config.motionSampleInterval = 10
        config.pressureSampleInterval = 10

        let samples = try SyntheticFlightLog.generate(config)
        let locations = samples.compactMap { sample -> LocationSample? in
            if case .location(let s) = sample { return s }
            return nil
        }

        let duringTaxi = locations.first { $0.timestamp < departure.addingTimeInterval(60) }
        #expect(duringTaxi?.speed == nil) // near-zero speed reports as nil, per the generator's convention

        let midFlight = locations.first { $0.timestamp > departure.addingTimeInterval(45 * 60) }
        #expect((midFlight?.speed ?? 0) > 200) // cruising near 240 m/s
    }
}
