import SwiftUI
import ContrailLog
import ContrailIdentity

/// ROADMAP Phase 2 -- Identity, redesigned as a hub: your profile, what your flight
/// history says about you, and the two social surfaces (Group Flight, Nearby
/// Passengers) that used to be separate top-level tabs. Generated stats use the
/// same instrument-tile styling as `InstrumentsSurface` deliberately -- they're
/// computed from real logged flights, not self-reported, so they earn the same
/// "measured/derived" treatment as a groundspeed readout, not plain list rows.
struct ProfileSurface: View {
    @Environment(AppModel.self) private var model

    @State private var displayName = ""
    @State private var homeBaseICAO = ""
    @State private var bio = ""
    @State private var didLoadProfile = false
    @State private var isEditing = false

    var body: some View {
        List {
            Section {
                identityCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if isEditing {
                Section("About You") {
                    TextField("Display name", text: $displayName)
                        .textInputAutocapitalization(.words)
                    TextField("Home base ICAO (optional)", text: $homeBaseICAO)
                        .textInputAutocapitalization(.characters)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...8)
                    Button("Save") { saveProfile() }
                }
            }

            Section {
                generatedStatsContent
            } header: {
                Text("Generated From Your Flights")
            } footer: {
                Text(
                    "Computed from every flight you've logged. Nothing here is "
                    + "self-reported — it's derived, which is what makes it "
                    + "interesting."
                )
            }

            Section("Share") {
                shareLatestFlightRow
            }

            Section {
                NavigationLink {
                    InsightsSurface()
                } label: {
                    FeatureCard(
                        title: "Insights", subtitle: "Route stats, forecast skill, aircraft & seat comparison",
                        systemImage: "chart.xyaxis.line", signal: ContrailSignal.amber
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    GroupFlightSurface()
                } label: {
                    FeatureCard(
                        title: "Group Flight", subtitle: "Combine your trace with a fellow passenger's",
                        systemImage: "person.2", signal: ContrailSignal.cyan
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DiscoverySurface()
                } label: {
                    FeatureCard(
                        title: "Nearby Passengers", subtitle: "Find others running Contrail on your flight",
                        systemImage: "person.2.wave.2", signal: ContrailSignal.green
                    )
                }
                .buttonStyle(.plain)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
        .navigationTitle("You")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") { isEditing.toggle() }
            }
        }
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

    private var identityCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(ContrailSignal.cyan)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.profile.displayName.isEmpty ? "Add your name" : model.profile.displayName)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(model.profile.displayName.isEmpty ? .secondary : .primary)
                if let homeBase = model.profile.homeBaseICAO, !homeBase.isEmpty {
                    Label(homeBase, systemImage: "house")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !model.profile.bio.isEmpty {
                    Text(model.profile.bio)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 4)
    }

    private func saveProfile() {
        model.updateProfile(
            UserProfile(
                displayName: displayName,
                homeBaseICAO: homeBaseICAO.isEmpty ? nil : homeBaseICAO.uppercased(),
                bio: bio
            )
        )
        isEditing = false
    }

    @ViewBuilder
    private var generatedStatsContent: some View {
        let stats = model.generatedProfileStats
        if stats.flightsLogged == 0 {
            Text("Log a flight to start building this out.")
                .foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                InstrumentTile(
                    label: "FLIGHTS", value: "\(stats.flightsLogged)", unit: nil, signal: ContrailSignal.cyan
                )
                InstrumentTile(
                    label: "HOURS", value: String(format: "%.1f", stats.hoursAtAltitude), unit: "hr",
                    signal: ContrailSignal.cyan
                )
                InstrumentTile(
                    label: "DISTANCE", value: String(format: "%.0f", stats.totalDistanceNauticalMiles), unit: "nm",
                    signal: ContrailSignal.cyan
                )
                if let averageDelta = stats.averageScheduleDeltaSeconds {
                    InstrumentTile(
                        label: "SCHEDULE", value: scheduleDeltaValue(averageDelta), unit: "min",
                        signal: averageDelta <= 0 ? ContrailSignal.green : ContrailSignal.amber
                    )
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .padding(.horizontal)

            if let luckDelta = stats.turbulenceLuckDelta {
                luckBadge(luckDelta)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.horizontal)
                    .padding(.top, 2)
            }

            ForEach(stats.routes) { route in
                LabeledContent(route.route, value: "\(route.count)×")
            }
            if let roughest = stats.roughestRoute, let edr = roughest.averageEDRCubeRoot {
                LabeledContent("Roughest route") {
                    Text("\(roughest.route) · \(String(format: "%.2f", edr)) EDR^(1/3)")
                }
            }
            if let smoothest = stats.smoothestRoute, let edr = smoothest.averageEDRCubeRoot {
                LabeledContent("Smoothest route") {
                    Text("\(smoothest.route) · \(String(format: "%.2f", edr)) EDR^(1/3)")
                }
            }
        }
    }

    /// §4.3's residual sign, restated as the "genuinely charming statistical
    /// observation" ROADMAP Phase 2 calls for: negative means smoother than GTG
    /// predicted, across every flight with forecast data.
    @ViewBuilder
    private func luckBadge(_ delta: Double) -> some View {
        let isNeutral = abs(delta) < 0.02
        let isLucky = delta < 0
        let signal: Color = isNeutral ? .secondary : (isLucky ? ContrailSignal.green : ContrailSignal.amber)
        let verdict = isNeutral ? "Average" : (isLucky ? "Lucky" : "Cursed")

        HStack(spacing: 12) {
            Image(systemName: isNeutral ? "equal.circle.fill" : (isLucky ? "cloud.fill" : "bolt.fill"))
                .font(.title2)
                .foregroundStyle(signal)
            VStack(alignment: .leading, spacing: 2) {
                Text("Turbulence luck: \(verdict)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(
                    isNeutral
                        ? "Your flights run about what GTG predicts."
                        : "Your flights run \(String(format: "%.2f", abs(delta))) EDR^(1/3) "
                            + (isLucky ? "smoother" : "rougher") + " than GTG predicts, on average."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(signal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func scheduleDeltaValue(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        return minutes >= 0 ? "+\(minutes)" : "\(minutes)"
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
