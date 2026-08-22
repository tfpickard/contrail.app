import Foundation
import Testing
import ContrailCore
import ContrailGeo
import ContrailSensors
import ContrailEstimator
@testable import ContrailLog

private let den = Coordinate(latitude: 39.8617, longitude: -104.6731)
private let lax = Coordinate(latitude: 33.9416, longitude: -118.4085)
private let departure = Date(timeIntervalSince1970: 1_755_639_600)

/// Runs the estimator over a short slice of the synthetic flight and returns the
/// resulting `EstimatorOutput`s — real, representative data rather than
/// hand-constructed fixtures, so these tests exercise the actual wire format the app
/// will produce.
private func sampleOutputs(count: Int = 20) throws -> [EstimatorOutput] {
    let plan = try FlightPlan(
        flightNumber: "UA1234", origin: den, destination: lax,
        scheduledDeparture: departure, scheduledArrival: departure.addingTimeInterval(8400),
        aircraftICAOType: "B738", aircraftRegistration: nil
    )
    let estimator = Estimator(flightPlan: plan) { _ in
        BearingToPlace(name: "Ely, Nevada", bearing: 190, distance: 67_600)
    }
    var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
    config.locationSampleInterval = 5
    config.motionSampleInterval = 30
    config.pressureSampleInterval = 30
    let samples = try SyntheticFlightLog.generate(config)

    var outputs: [EstimatorOutput] = []
    for sample in samples {
        if let output = estimator.ingest(sample) {
            outputs.append(output)
            if outputs.count >= count { break }
        }
    }
    return outputs
}

struct LogRecordTests {
    @Test func roundTripPreservesAllFields() throws {
        let outputs = try sampleOutputs(count: 5)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for output in outputs {
            let record = LogRecord(output: output)
            let data = try encoder.encode(record)
            let decoded = try decoder.decode(LogRecord.self, from: data)
            #expect(decoded == record)
        }
    }

    @Test func wireFormatUsesCompactKeysAndCoordinateArrays() throws {
        let outputs = try sampleOutputs(count: 1)
        let record = LogRecord(output: outputs[0])
        let data = try JSONEncoder().encode(record)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Top-level compact keys, per the plan's schema.
        #expect(object?.keys.contains("v") == true)
        #expect(object?.keys.contains("k") == true)
        #expect(object?.keys.contains("pos") == true)
        #expect(object?.keys.contains("mot") == true)
        #expect(object?.keys.contains("cab") == true)
        #expect(object?.keys.contains("rte") == true)

        // Coordinates encode as [lat, lon] arrays, not {"latitude":...,"longitude":...}.
        let pos = object?["pos"] as? [String: Any]
        let fu = pos?["fu"] as? [String: Any]
        let value = fu?["value"] as? [Double]
        #expect(value?.count == 2)
    }

    /// {1,0} lines predate `outsideAir` entirely -- no "oat" key at all, not even a
    /// null one. §6's "remains parseable even if the schema drifts" promise, checked
    /// directly: an old line must still decode, with the new field honestly absent.
    @Test func decodingAPreOutsideAirLineFallsBackToUnavailable() throws {
        let legacyLine = """
        {"v":[1,0],"k":"s","t":1755640000.0,"u":8123.4,
         "pos":{"fu":{"value":null,"source":"unavailable","age":null},
                "cr":{"value":null,"source":"unavailable","age":null},
                "gn":{"value":null,"source":"unavailable","age":null},
                "dr":{"value":null,"source":"unavailable","age":null},
                "ha":{"value":null,"source":"unavailable","age":null},
                "va":{"value":null,"source":"unavailable","age":null},
                "tsf":{"value":null,"source":"unavailable","age":null},
                "alt":{"value":null,"source":"unavailable","age":null}},
         "mot":{"gs":{"value":null,"source":"unavailable","age":null},
                "tc":{"value":null,"source":"unavailable","age":null},
                "tar":{"value":null,"source":"unavailable","age":null},
                "vs":{"value":null,"source":"unavailable","age":null},
                "la":{"value":null,"source":"unavailable","age":null},
                "cls":{"value":null,"source":"unavailable","age":null},
                "clc":{"value":null,"source":"unavailable","age":null}},
         "cab":{"p":{"value":null,"source":"unavailable","age":null},
                "pa":{"value":null,"source":"unavailable","age":null},
                "pr":{"value":null,"source":"unavailable","age":null}},
         "trb":{"edr":{"value":null,"source":"unavailable","age":null},
                "fedr":{"value":null,"source":"unavailable","age":null},
                "gate":{"value":null,"source":"unavailable","age":null}},
         "rte":{"atf":{"value":null,"source":"unavailable","age":null},
                "atr":{"value":null,"source":"unavailable","age":null},
                "xte":{"value":null,"source":"unavailable","age":null},
                "fp":{"value":null,"source":"unavailable","age":null},
                "city":{"value":null,"source":"unavailable","age":null},
                "eta":{"value":null,"source":"unavailable","age":null}},
         "ph":{"value":null,"source":"unavailable","age":null}}
        """
        let record = try JSONDecoder().decode(LogRecord.self, from: Data(legacyLine.utf8))
        #expect(record.outsideAir == .unavailable)
    }

    @Test func unavailableTurbulenceChannelsEncodeAsExplicitNull() throws {
        let outputs = try sampleOutputs(count: 1)
        let record = LogRecord(output: outputs[0])
        let data = try JSONEncoder().encode(record)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let trb = object?["trb"] as? [String: Any]
        let edr = trb?["edr"] as? [String: Any]
        #expect(edr?.keys.contains("value") == true)
        #expect(edr?["value"] is NSNull)
    }
}

struct NDJSONLogTests {
    @Test func writeThenReadRoundTripsAllRecords() throws {
        let outputs = try sampleOutputs(count: 10)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("contrail-log-test-\(UUID().uuidString).ndjson")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let writer = try NDJSONLogWriter(fileURL: tempURL)
        for output in outputs {
            try writer.append(LogRecord(output: output))
        }
        try writer.flush()
        try writer.close()

        let read = try NDJSONLogReader.readAll(from: tempURL)
        #expect(read.count == outputs.count)
        for (original, roundTripped) in zip(outputs, read) {
            #expect(roundTripped == LogRecord(output: original))
        }
    }

    @Test func appendIsTrulyAppendOnlyAcrossWriterInstances() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("contrail-log-append-\(UUID().uuidString).ndjson")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let outputs = try sampleOutputs(count: 4)
        let firstWriter = try NDJSONLogWriter(fileURL: tempURL)
        try firstWriter.append(LogRecord(output: outputs[0]))
        try firstWriter.append(LogRecord(output: outputs[1]))
        try firstWriter.flush()
        try firstWriter.close()

        // Simulates the app reopening the same flight's log after a relaunch.
        let secondWriter = try NDJSONLogWriter(fileURL: tempURL)
        try secondWriter.append(LogRecord(output: outputs[2]))
        try secondWriter.append(LogRecord(output: outputs[3]))
        try secondWriter.flush()
        try secondWriter.close()

        let read = try NDJSONLogReader.readAll(from: tempURL)
        #expect(read.count == 4)
    }

    /// §6's crash-safety property, verified directly: a truncated final line (the
    /// artifact a crash mid-write would leave) costs at most that one line, never the
    /// rest of the file.
    @Test func truncatedFinalLineDoesNotInvalidateEarlierLines() throws {
        let outputs = try sampleOutputs(count: 6)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("contrail-log-truncate-\(UUID().uuidString).ndjson")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let writer = try NDJSONLogWriter(fileURL: tempURL)
        for output in outputs {
            try writer.append(LogRecord(output: output))
        }
        try writer.flush()
        try writer.close()

        // Simulate a crash mid-write: chop the last line off partway through.
        var data = try Data(contentsOf: tempURL)
        let cutPoint = data.count - 20
        data = data.prefix(cutPoint)
        try data.write(to: tempURL)

        let read = try NDJSONLogReader.readAll(from: tempURL)
        #expect(read.count == outputs.count - 1)
        for (original, roundTripped) in zip(outputs, read) {
            #expect(roundTripped == LogRecord(output: original))
        }
    }

    @Test func corruptionInAnEarlierLineIsNotTolerated() throws {
        let text = """
        {"v":[1,0],"k":"s","t":1,"u":1,"pos":{}}
        {this is not valid json at all
        {"v":[1,0],"k":"s","t":2,"u":2,"pos":{}}
        """
        #expect(throws: (any Error).self) {
            try NDJSONLogReader.readAll(fromContents: text)
        }
    }
}

struct LogExportTests {
    @Test func csvHasHeaderPlusOneRowPerSample() throws {
        let outputs = try sampleOutputs(count: 5)
        let records = outputs.map { LogRecord(output: $0) }
        let csv = LogExport.csv(records: records)
        let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)
        #expect(lines.count == records.count + 1) // header + rows
        #expect(lines[0].hasPrefix("timestamp,phase,latitude,longitude"))
    }

    @Test func jsonArrayExportIsAValidJSONArrayOfTheSameLength() throws {
        let outputs = try sampleOutputs(count: 3)
        let records = outputs.map { LogRecord(output: $0) }
        let data = try LogExport.jsonArray(records: records)
        let array = try JSONSerialization.jsonObject(with: data) as? [Any]
        #expect(array?.count == records.count)
    }
}
