import Foundation
import Testing
import ContrailCore
import ContrailGeo
@testable import ContrailSensors

struct ReplaySensorSourceTests {
    @Test func replaysAllSamplesInTimeOrder() async {
        let base = Date(timeIntervalSince1970: 1_755_639_600)
        let samples: [RawSensorSample] = [
            .pressure(PressureSample(timestamp: base.addingTimeInterval(2), kilopascals: 101.3)),
            .location(LocationSample(
                timestamp: base, coordinate: Coordinate(latitude: 0, longitude: 0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, speed: nil, course: nil
            )),
            .motion(MotionSample(
                timestamp: base.addingTimeInterval(1),
                userAcceleration: Vector3(x: 0, y: 0, z: 0),
                gravity: Vector3(x: 0, y: 0, z: -1),
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
                rotationRate: Vector3(x: 0, y: 0, z: 0)
            )),
        ]
        // 1000x speed so the test doesn't actually wait ~2 seconds.
        let source = ReplaySensorSource(samples: samples, speedMultiplier: 1000)

        var received: [RawSensorSample] = []
        for await sample in source.samples() {
            received.append(sample)
        }

        #expect(received.count == 3)
        #expect(received.map(\.timestamp) == received.map(\.timestamp).sorted())
        if case .location = received[0] {} else { Issue.record("expected location first") }
        if case .motion = received[1] {} else { Issue.record("expected motion second") }
        if case .pressure = received[2] {} else { Issue.record("expected pressure third") }
    }

    @Test func emptySourceFinishesImmediately() async {
        let source = ReplaySensorSource(samples: [], speedMultiplier: 1)
        var count = 0
        for await _ in source.samples() { count += 1 }
        #expect(count == 0)
    }

    @Test func stoppingIterationEarlyDoesNotHang() async {
        let base = Date(timeIntervalSince1970: 1_755_639_600)
        // Widely spaced samples at real-time speed; breaking early must not wait for
        // the full log to play out.
        let samples: [RawSensorSample] = (0..<5).map { i in
            .location(LocationSample(
                timestamp: base.addingTimeInterval(Double(i) * 3600),
                coordinate: Coordinate(latitude: 0, longitude: 0),
                altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, speed: nil, course: nil
            ))
        }
        let source = ReplaySensorSource(samples: samples, speedMultiplier: 1)
        var count = 0
        for await _ in source.samples() {
            count += 1
            if count == 1 { break }
        }
        #expect(count == 1)
    }

    @Test func codableRoundTripPreservesAllThreeSampleKinds() throws {
        let base = Date(timeIntervalSince1970: 1_755_639_600)
        let original: [RawSensorSample] = [
            .location(LocationSample(
                timestamp: base, coordinate: Coordinate(latitude: 39.8617, longitude: -104.6731),
                altitude: 1655, horizontalAccuracy: 8, verticalAccuracy: 12, speed: 5.2, course: 90.0
            )),
            .motion(MotionSample(
                timestamp: base, userAcceleration: Vector3(x: 0.01, y: -0.02, z: 0.03),
                gravity: Vector3(x: 0, y: 0, z: -1),
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
                rotationRate: Vector3(x: 0, y: 0, z: 0.001)
            )),
            .pressure(PressureSample(timestamp: base, kilopascals: 78.9)),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for sample in original {
            let data = try encoder.encode(sample)
            let decoded = try decoder.decode(RawSensorSample.self, from: data)
            #expect(decoded == sample)
        }
    }
}
