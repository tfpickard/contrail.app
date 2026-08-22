import SwiftUI
import ContrailCore
import ContrailGeo
import ContrailData

/// §5.1/§5's pre-flight screen: manual entry (the `FlightResolver` protocol's
/// AeroAPI-backed conformance is a later phase — see the session's build notes),
/// resolved against the bundled airport index, with the per-asset verified state
/// §5 requires ("not a hopeful one") shown directly rather than assumed.
struct PreFlightSurface: View {
    @Environment(AppModel.self) private var model

    @State private var flightNumber = ""
    @State private var originICAO = ""
    @State private var destinationICAO = ""
    @State private var aircraftType = ""
    @State private var scheduledDeparture = Date()
    @State private var scheduledArrival = Date().addingTimeInterval(2 * 3600)
    @State private var validationError: String?
    @State private var isConfirmingStop = false

    var body: some View {
        Group {
            if model.isFlightActive {
                inFlightView
            } else {
                preFlightForm
            }
        }
        .navigationTitle("Contrail")
    }

    /// Shown for the entire flight -- without this, `AppModel.stopFlight()` is
    /// unreachable from the UI once a flight starts, and the only way to end one is
    /// to kill the app. `NDJSONLogWriter`'s lifecycle is still owned end-to-end by
    /// `FlightEstimationEngine` (per its own doc comment); this button just cancels
    /// the run task, which triggers that engine's own `defer` flush/close.
    private var inFlightView: some View {
        Form {
            if let plan = model.flightPlan {
                Section("Flight") {
                    LabeledContent("Flight", value: plan.flightNumber)
                    if let progress = model.latestOutput?.route.fractionalProgress.value {
                        LabeledContent("Progress", value: "\(Int((progress * 100).rounded()))%")
                    }
                    if let phase = model.latestOutput?.phase.value {
                        LabeledContent("Phase", value: phase.rawValue.capitalized)
                    }
                }
            }

            Section {
                NavigationLink {
                    CameraSurface()
                } label: {
                    FeatureCard(
                        title: "Camera", subtitle: "Capture a geotagged, captioned photo",
                        systemImage: "camera", signal: ContrailSignal.cyan
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    RouteIntelligenceSurface()
                } label: {
                    FeatureCard(
                        title: "Route", subtitle: "ARTCC jurisdiction, on-route fixes, divert options",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                        signal: ContrailSignal.green
                    )
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .padding(.horizontal)
            .padding(.vertical, 2)

            Section("Turbulence Forecast") {
                forecastStatusRow
            }

            if let lastLogError = model.lastLogError {
                Section {
                    Label(lastLogError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(ContrailSignal.amber)
                }
            }

            Section {
                Button("Stop Flight", role: .destructive) { isConfirmingStop = true }
            }
        }
        .confirmationDialog(
            "Stop logging this flight?", isPresented: $isConfirmingStop, titleVisibility: .visible
        ) {
            Button("Stop Flight", role: .destructive) { model.stopFlight() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The log so far is saved. You can review and export it from the Flight Log tab.")
        }
    }

    private var preFlightForm: some View {
        Form {
            Section("Assets") {
                assetRow("Airports", status: model.airportAssetStatus)
                assetRow("Populated places", status: model.placeAssetStatus)
                assetRow("Fixes & navaids", status: model.navFixAssetStatus)
                assetRow("ARTCC boundaries", status: model.artccAssetStatus)
            }

            Section("Flight") {
                TextField("Flight number", text: $flightNumber)
                    .textInputAutocapitalization(.characters)
                TextField("Origin ICAO", text: $originICAO)
                    .textInputAutocapitalization(.characters)
                TextField("Destination ICAO", text: $destinationICAO)
                    .textInputAutocapitalization(.characters)
                TextField("Aircraft type (optional)", text: $aircraftType)
                    .textInputAutocapitalization(.characters)
            }

            Section("Schedule") {
                DatePicker("Departure", selection: $scheduledDeparture)
                DatePicker("Arrival", selection: $scheduledArrival)
            }

            Section {
                SecureField("GribStream API token (optional)", text: gribStreamTokenBinding)
            } footer: {
                Text(
                    "§4.2/§4.3: compares measured turbulence against NOAA's GTG "
                    + "forecast along your route. Requires your own free GribStream "
                    + "account (gribstream.com) -- left blank, the app logs and "
                    + "shows measured turbulence only."
                )
            }

            if let validationError {
                Section {
                    Label(validationError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(ContrailSignal.amber)
                }
            }

            Section {
                Button("Start Flight") { startFlight() }
                    .disabled(flightNumber.isEmpty || originICAO.isEmpty || destinationICAO.isEmpty)
            }
        }
    }

    private var gribStreamTokenBinding: Binding<String> {
        Binding(get: { model.gribStreamAPIToken }, set: { model.gribStreamAPIToken = $0 })
    }

    @ViewBuilder
    private var forecastStatusRow: some View {
        switch model.forecastFetchStatus {
        case .idle:
            Text(model.gribStreamAPIToken.isEmpty ? "No API token configured." : "Not yet fetched.")
                .foregroundStyle(.secondary)
        case .fetching:
            LabeledContent("Fetching forecast") { ProgressView() }
        case .succeeded(let count):
            Label("\(count) forecast points along route", systemImage: "checkmark.circle.fill")
                .foregroundStyle(ContrailSignal.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(ContrailSignal.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func assetRow(_ name: String, status: AppModel.AssetStatus) -> some View {
        HStack {
            Text(name)
            Spacer()
            switch status {
            case .pending:
                ProgressView()
            case .verified(let count):
                Label("\(count) records", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(ContrailSignal.green)
                    .labelStyle(.titleAndIcon)
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(ContrailSignal.red)
                    .lineLimit(1)
            }
        }
        .font(.footnote)
    }

    private func startFlight() {
        validationError = nil

        guard let origin = model.airport(icao: originICAO.uppercased()) else {
            validationError = "Unknown origin ICAO code: \(originICAO.uppercased())"
            return
        }
        guard let destination = model.airport(icao: destinationICAO.uppercased()) else {
            validationError = "Unknown destination ICAO code: \(destinationICAO.uppercased())"
            return
        }
        guard scheduledArrival > scheduledDeparture else {
            validationError = "Arrival must be after departure."
            return
        }

        do {
            let plan = try FlightPlan(
                flightNumber: flightNumber.uppercased(),
                origin: origin.coordinate,
                destination: destination.coordinate,
                scheduledDeparture: scheduledDeparture,
                scheduledArrival: scheduledArrival,
                aircraftICAOType: aircraftType.isEmpty ? nil : aircraftType.uppercased(),
                aircraftRegistration: nil
            )
            model.startFlight(plan, origin: origin, destination: destination)
        } catch {
            validationError = "Could not compute the route: \(error)"
        }
    }
}
