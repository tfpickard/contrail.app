import SwiftUI
import Charts
import UniformTypeIdentifiers
import ContrailLog
import ContrailIdentity

extension UTType {
    /// Not declared in the app's Info.plist (no `UTExportedTypeDeclarations` entry) --
    /// a dynamic type is enough for `fileImporter`/`ShareLink` to filter and hand off
    /// correctly, at the cost of Files.app not showing a custom icon for it. That
    /// trade is fine here: this format only ever moves phone-to-phone, never sits in
    /// a folder waiting to be double-tapped.
    static let contrailFlightPackage = UTType(exportedAs: "app.contrail.flightpackage", conformingTo: .json)
}

/// ROADMAP Phase 2's "group flight records": several people on the same flight,
/// each running the app, producing one combined record. Phase 3's networked
/// discovery doesn't exist yet, so combining happens the way AirDrop already lets
/// two strangers on a plane exchange a file today -- export your own flight as a
/// `.contrailflight` package, share it, and import whatever a fellow passenger
/// sends back. `GroupFlightBuilder` refuses to combine anything that doesn't
/// genuinely claim the same flight.
struct GroupFlightSurface: View {
    @Environment(AppModel.self) private var model

    @State private var flights: [FlightLogStore.FlightSummary] = []
    @State private var selectedFlightID: String?
    @State private var ownPackage: FlightExportPackage?
    @State private var exportURL: URL?
    @State private var importedPackages: [FlightExportPackage] = []
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var groupRecord: GroupFlightRecord?

    var body: some View {
        Form {
            Section("Your Flight") {
                if flights.isEmpty {
                    Text("Log a flight first, then come back here to build a group record.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Flight", selection: $selectedFlightID) {
                        Text("Select…").tag(String?.none)
                        ForEach(flights) { flight in
                            Text(flightLabel(flight)).tag(Optional(flight.id))
                        }
                    }
                    .onChange(of: selectedFlightID) { _, _ in resetGroup() }
                }
            }

            if let selectedFlight {
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Send to a Fellow Passenger", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button("Prepare Export") { prepareExport(for: selectedFlight) }
                    }
                } footer: {
                    Text(
                        "AirDrop, Messages, or any share sheet destination -- whoever "
                        + "receives this file imports it below."
                    )
                }

                Section("Participants") {
                    Label(
                        model.profile.displayName.isEmpty ? "You" : model.profile.displayName,
                        systemImage: "person.fill"
                    )
                    ForEach(importedPackages, id: \.participantName) { package in
                        Label(package.participantName, systemImage: "person.fill.badge.plus")
                    }
                    Button("Import Participant…") { isImporting = true }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if let groupRecord {
                    Section("Turbulence, By Seat") {
                        turbulenceComparisonChart(for: groupRecord)
                    }
                }
            }
        }
        .navigationTitle("Group Flight")
        .onAppear { flights = FlightLogStore.listFlights() }
        .fileImporter(
            isPresented: $isImporting, allowedContentTypes: [.contrailFlightPackage, .json]
        ) { result in
            handleImport(result)
        }
    }

    private var selectedFlight: FlightLogStore.FlightSummary? {
        flights.first { $0.id == selectedFlightID }
    }

    private func flightLabel(_ flight: FlightLogStore.FlightSummary) -> String {
        guard let manifest = flight.manifest else { return flight.id }
        return "\(manifest.flight.number) — \(manifest.flight.origin.icao)→\(manifest.flight.destination.icao)"
    }

    private func prepareExport(for flight: FlightLogStore.FlightSummary) {
        errorMessage = nil
        do {
            guard let manifest = flight.manifest else {
                errorMessage = "This flight has no manifest to export."
                return
            }
            let records = try FlightLogStore.loadRecords(in: flight.directory)
            let name = model.profile.displayName.isEmpty ? "Pilot" : model.profile.displayName
            let package = FlightExportPackage(participantName: name, manifest: manifest, records: records)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(flight.id)-\(name).contrailflight")
            try package.encoded().write(to: url, options: .atomic)
            ownPackage = package
            exportURL = url
            rebuildGroupRecordIfPossible()
        } catch {
            errorMessage = "Could not prepare export: \(error)"
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        errorMessage = nil
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let package = try FlightExportPackage.decode(data)

            guard let selectedFlight, let manifest = selectedFlight.manifest else {
                errorMessage = "Select your own flight before importing a participant."
                return
            }
            guard GroupFlightMatcher.sameFlight(manifest, package.manifest) else {
                errorMessage = "\(package.participantName)'s file is a different flight "
                    + "(\(package.manifest.flight.number) on \(package.manifest.flight.date))."
                return
            }
            importedPackages.append(package)
            rebuildGroupRecordIfPossible()
        } catch {
            errorMessage = "Could not import that file: \(error)"
        }
    }

    private func rebuildGroupRecordIfPossible() {
        guard let ownPackage, !importedPackages.isEmpty else {
            groupRecord = nil
            return
        }
        groupRecord = try? GroupFlightBuilder.build(from: [ownPackage] + importedPackages)
    }

    private func resetGroup() {
        ownPackage = nil
        exportURL = nil
        importedPackages = []
        groupRecord = nil
        errorMessage = nil
    }

    @ViewBuilder
    private func turbulenceComparisonChart(for record: GroupFlightRecord) -> some View {
        let points = GroupTurbulenceComparison.compare(record)
        if points.isEmpty {
            Text("No overlapping turbulence data between participants yet.")
                .foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(points, id: \.bucketStart) { point in
                    ForEach(point.values.sorted { $0.key < $1.key }, id: \.key) { name, value in
                        LineMark(
                            x: .value("Time", point.bucketStart),
                            y: .value("EDR^(1/3)", value)
                        )
                        .foregroundStyle(by: .value("Participant", name))
                    }
                }
            }
            .frame(height: 220)
        }
    }
}
