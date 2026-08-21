import SwiftUI
import ContrailData

/// §5.3–§5.5: current ARTCC jurisdiction, named fixes/navaids along the filed
/// route, and glide-reach divert candidates -- all computed by
/// `RouteIntelligenceEngine` from the bundled FAA NASR datasets, entirely offline.
struct RouteIntelligenceSurface: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if !model.isFlightActive {
                ContentUnavailableView(
                    "No Active Flight", systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                    description: Text("Start a flight to see ARTCC jurisdiction, on-route fixes, and divert options.")
                )
            } else {
                artccSection
                divertSection
                onRouteFixesSection
            }
        }
        .navigationTitle("Route")
    }

    @ViewBuilder
    private var artccSection: some View {
        Section("ARTCC Jurisdiction") {
            if let artcc = model.currentARTCC {
                LabeledContent("Center", value: "\(artcc.id) — \(artcc.name.capitalized)")
                LabeledContent("Tier", value: artcc.altitudeTier.rawValue.capitalized)
            } else {
                Text("Outside all published ARTCC boundaries.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var divertSection: some View {
        Section {
            if model.divertCandidates.isEmpty {
                Text("No airports currently within estimated glide range.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.divertCandidates.prefix(10)) { candidate in
                    divertRow(candidate)
                }
            }
        } header: {
            Text("Divert Options")
        } footer: {
            Text("Glide range assumes a 17:1 glide ratio -- a representative estimate, not a figure specific to your aircraft.")
        }
    }

    private func divertRow(_ candidate: RouteIntelligenceEngine.DivertCandidate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.airport.icao)
                    .font(.headline)
                Text(candidate.airport.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f nm", candidate.distance / 1852))
                Text(String(format: "%03.0f°", candidate.bearing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: candidate.reachable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(candidate.reachable ? .green : .orange)
        }
    }

    @ViewBuilder
    private var onRouteFixesSection: some View {
        Section("On-Route Fixes") {
            if model.onRouteFixes.isEmpty {
                Text("No published fixes or navaids within the route corridor.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.onRouteFixes.prefix(25)) { onRoute in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(onRoute.fix.id)
                                .font(.headline)
                            if let name = onRoute.fix.name {
                                Text(name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(String(format: "%.0f nm", onRoute.alongTrackFlown / 1852))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
