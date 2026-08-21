import Foundation
import ContrailLog

/// Enumerates completed (and in-progress) flight log directories under
/// `Documents/Flights/`, and exports a given flight's NDJSON as CSV/JSON on demand
/// (§6: "provide CSV and JSON export via the share sheet"). Read-only -- writing a
/// flight's log belongs entirely to `AppModel`/`FlightEstimationEngine`; this type
/// never touches `samples.ndjson` while a flight might still be appending to it.
enum FlightLogStore {
    struct FlightSummary: Identifiable, Sendable {
        let id: String // flightID, i.e. the directory name
        let directory: URL
        let manifest: FlightManifest?
    }

    static func listFlights() -> [FlightSummary] {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return [] }
        let flightsDirectory = documents.appendingPathComponent("Flights", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: flightsDirectory, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Sorted by modification date, not by parsing the flightID string -- flight
        // numbers vary in length and format, so a lexical sort on "<number>-<date>"
        // isn't reliably chronological the way the directory's own mtime is.
        let dated: [(FlightSummary, Date)] = entries.compactMap { directory in
            let values = try? directory.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            let manifest = try? loadManifest(in: directory)
            let summary = FlightSummary(id: directory.lastPathComponent, directory: directory, manifest: manifest)
            return (summary, values?.contentModificationDate ?? .distantPast)
        }
        return dated.sorted { $0.1 > $1.1 }.map(\.0)
    }

    static func loadManifest(in directory: URL) throws -> FlightManifest {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        return try JSONDecoder().decode(FlightManifest.self, from: data)
    }

    static func loadRecords(in directory: URL) throws -> [LogRecord] {
        try NDJSONLogReader.readAll(from: directory.appendingPathComponent("samples.ndjson"))
    }

    static func exportCSV(for summary: FlightSummary) throws -> Data {
        Data(LogExport.csv(records: try loadRecords(in: summary.directory)).utf8)
    }

    static func exportJSON(for summary: FlightSummary) throws -> Data {
        try LogExport.jsonArray(records: try loadRecords(in: summary.directory))
    }
}
