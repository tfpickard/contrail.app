import SwiftUI
import ContrailLog

/// §6's "provide CSV and JSON export via the share sheet" -- the one UI surface that
/// makes a landed flight's log actually retrievable. Lists everything under
/// `Documents/Flights/`; each flight's CSV/JSON is generated on demand from its
/// NDJSON when the row expands, never cached, since the NDJSON file (not the export)
/// remains the single source of truth.
struct FlightLogSurface: View {
    @State private var flights: [FlightLogStore.FlightSummary] = []

    var body: some View {
        List {
            if flights.isEmpty {
                ContentUnavailableView(
                    "No Flights Logged Yet", systemImage: "doc.text",
                    description: Text("Flights you log appear here once you tap Start Flight.")
                )
            }
            ForEach(flights) { flight in
                FlightLogRow(flight: flight)
            }
        }
        .navigationTitle("Flight Log")
        .onAppear { refresh() }
        .refreshable { refresh() }
    }

    private func refresh() {
        flights = FlightLogStore.listFlights()
    }
}

private struct FlightLogRow: View {
    let flight: FlightLogStore.FlightSummary

    @State private var isExpanded = false
    @State private var csvURL: URL?
    @State private var jsonURL: URL?
    @State private var exportError: String?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let manifest = flight.manifest {
                    LabeledContent("Aircraft", value: manifest.flight.aircraft.icaoType ?? "—")
                    LabeledContent("Scheduled departure", value: manifest.flight.scheduled.departure.formatted())
                    LabeledContent("Sensor source", value: manifest.sensorSource)
                }
                HStack(spacing: 16) {
                    exportLink(title: "CSV", systemImage: "tablecells", url: csvURL)
                    exportLink(title: "JSON", systemImage: "curlybraces", url: jsonURL)
                }
                if let exportError {
                    Label(exportError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }
            .padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded, csvURL == nil, jsonURL == nil {
                prepareExports()
            }
        }
    }

    private var title: String {
        flight.manifest?.flight.number ?? flight.id
    }

    private var subtitle: String {
        guard let manifest = flight.manifest else { return "No manifest" }
        return "\(manifest.flight.origin.icao) → \(manifest.flight.destination.icao)"
    }

    @ViewBuilder
    private func exportLink(title: String, systemImage: String, url: URL?) -> some View {
        if let url {
            ShareLink(item: url) {
                Label(title, systemImage: systemImage)
            }
        } else {
            ProgressView()
        }
    }

    private func prepareExports() {
        do {
            csvURL = try writeTemp(data: FlightLogStore.exportCSV(for: flight), filename: "\(flight.id).csv")
            jsonURL = try writeTemp(data: FlightLogStore.exportJSON(for: flight), filename: "\(flight.id).json")
        } catch {
            exportError = "Could not prepare export: \(error)"
        }
    }

    private func writeTemp(data: Data, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }
}
