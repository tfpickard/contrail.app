import SwiftUI
import ContrailLog
import ContrailIdentity

/// ROADMAP Phase 2 -- Identity. Two halves, kept visually distinct: "About You" is
/// freeform and editable, "Generated From Your Flights" is computed from logged
/// flights and never touched by the user -- the same "self-reported vs. derived"
/// split `UserProfile`/`GeneratedProfileStats` draw in code.
struct ProfileSurface: View {
    @Environment(AppModel.self) private var model

    @State private var displayName = ""
    @State private var homeBaseICAO = ""
    @State private var bio = ""
    @State private var didLoadProfile = false

    var body: some View {
        Form {
            Section("About You") {
                TextField("Display name", text: $displayName)
                    .textInputAutocapitalization(.words)
                TextField("Home base ICAO (optional)", text: $homeBaseICAO)
                    .textInputAutocapitalization(.characters)
                TextField("Bio", text: $bio, axis: .vertical)
                    .lineLimit(3...8)
                Button("Save Profile") { saveProfile() }
            }

            Section {
                generatedStatsContent
            } header: {
                Text("Generated From Your Flights")
            } footer: {
                Text(
                    "Computed from every flight you've logged. Nothing here is "
                    + "self-reported -- it's derived, which is what makes it "
                    + "interesting."
                )
            }

            Section("Share") {
                shareLatestFlightRow
            }
        }
        .navigationTitle("Profile")
        .onAppear {
            if !didLoadProfile {
                displayName = model.profile.displayName
                homeBaseICAO = model.profile.homeBaseICAO ?? ""
                bio = model.profile.bio
                didLoadProfile = true
            }
            model.refreshGeneratedProfileStats()
        }
        .refreshable { model.refreshGeneratedProfileStats() }
    }

    private func saveProfile() {
        model.updateProfile(
            UserProfile(
                displayName: displayName,
                homeBaseICAO: homeBaseICAO.isEmpty ? nil : homeBaseICAO.uppercased(),
                bio: bio
            )
        )
    }

    @ViewBuilder
    private var generatedStatsContent: some View {
        let stats = model.generatedProfileStats
        if stats.flightsLogged == 0 {
            Text("Log a flight to start building this out.")
                .foregroundStyle(.secondary)
        } else {
            LabeledContent("Flights logged", value: "\(stats.flightsLogged)")
            LabeledContent("Hours airborne", value: String(format: "%.1f", stats.hoursAtAltitude))
            LabeledContent(
                "Distance flown", value: String(format: "%.0f nm", stats.totalDistanceNauticalMiles)
            )
            ForEach(stats.routes) { route in
                LabeledContent(route.route, value: "\(route.count)×")
            }
            if let roughest = stats.roughestRoute, let edr = roughest.averageEDRCubeRoot {
                LabeledContent("Roughest route", value: "\(roughest.route) (\(String(format: "%.2f", edr)))")
            }
            if let smoothest = stats.smoothestRoute, let edr = smoothest.averageEDRCubeRoot {
                LabeledContent("Smoothest route", value: "\(smoothest.route) (\(String(format: "%.2f", edr)))")
            }
            if let luckDelta = stats.turbulenceLuckDelta {
                LabeledContent("Turbulence luck", value: luckDescription(luckDelta))
            }
            if let averageDelta = stats.averageScheduleDeltaSeconds {
                LabeledContent("Average schedule delta", value: scheduleDeltaDescription(averageDelta))
            }
        }
    }

    /// §4.3's residual sign, restated in plain language: negative means your
    /// flights consistently ran smoother than GTG predicted.
    private func luckDescription(_ delta: Double) -> String {
        let magnitude = String(format: "%.2f", abs(delta))
        if abs(delta) < 0.02 { return "About what forecasts predict" }
        return delta < 0 ? "Lucky, by \(magnitude)" : "Cursed, by \(magnitude)"
    }

    private func scheduleDeltaDescription(_ seconds: Double) -> String {
        let minutes = Int((abs(seconds) / 60).rounded())
        return seconds < 0 ? "\(minutes) min early, on average" : "\(minutes) min late, on average"
    }

    @ViewBuilder
    private var shareLatestFlightRow: some View {
        if let latest = FlightLogStore.listFlights().first, let manifest = latest.manifest {
            ShareLink(item: shareSummary(for: manifest)) {
                Label("Share Latest Flight", systemImage: "square.and.arrow.up")
            }
        } else {
            Text("No flights to share yet.").foregroundStyle(.secondary)
        }
    }

    /// A plain-text summary -- ROADMAP Phase 2: "sharing outward: flight summaries
    /// ... to the platforms the user chooses." `ShareLink` on a `String` already
    /// hands off to Messages/Mail/whatever the user picks, so there's no per-platform
    /// integration to build; this just decides what that text says.
    private func shareSummary(for manifest: FlightManifest) -> String {
        let flight = manifest.flight
        var lines = [
            "\(flight.number): \(flight.origin.icao) → \(flight.destination.icao)",
            "Flown \(flight.date) via Contrail",
        ]
        if let aircraft = flight.aircraft.icaoType {
            lines.append("Aircraft: \(aircraft)")
        }
        return lines.joined(separator: "\n")
    }
}
