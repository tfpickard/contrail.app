import SwiftUI
import ContrailCore

/// The redesigned home for everything §8 originally spread across four separate
/// tabs (Metrics, Statistics, Turbulence, Fix Quality). A glanceable live-data
/// dashboard up top -- big instrument tiles in aviation units (knots, feet, fpm),
/// not the SI units the log stores -- with the three deeper surfaces reachable as
/// real destinations, each still whole and self-contained (Turbulence keeps its
/// own honesty header, Fix Quality its own accuracy detail, Statistics its own
/// window picker). Consolidating the *navigation*, not the content.
struct InstrumentsSurface: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let output = model.latestOutput {
                Section("Live") {
                    tileGrid([
                        InstrumentTile(
                            label: "GS", value: fmt(knots(output.motion.groundspeed.value)), unit: "kt",
                            signal: ContrailSignal.cyan
                        ),
                        InstrumentTile(
                            label: "ALT", value: fmt(feet(output.position.altitudeGPS.value)), unit: "ft",
                            signal: ContrailSignal.cyan
                        ),
                        InstrumentTile(
                            label: "VS", value: fmtSigned(fpm(output.motion.verticalSpeed.value)), unit: "fpm",
                            signal: ContrailSignal.cyan
                        ),
                        InstrumentTile(
                            label: "XTK", value: fmtSigned(output.route.crossTrackError.value), unit: "m",
                            signal: .secondary
                        ),
                    ])
                }

                Section("Cabin") {
                    tileGrid([
                        InstrumentTile(
                            label: "CABIN P", value: fmt(output.cabin.pressure.value), unit: "kPa",
                            signal: ContrailSignal.cyan
                        ),
                        InstrumentTile(
                            label: "CABIN ALT", value: fmt(feet(output.cabin.pressureAltitude.value)), unit: "ft",
                            signal: ContrailSignal.cyan
                        ),
                    ])
                }

                Section {
                    tileGrid([
                        InstrumentTile(
                            label: "OAT", value: fmt(output.outsideAir.staticAirTemperature.value), unit: "°C",
                            signal: ContrailSignal.cyan
                        ),
                        InstrumentTile(
                            label: "TAS", value: fmt(knots(output.outsideAir.trueAirspeed.value)), unit: "kt",
                            signal: ContrailSignal.cyan
                        ),
                    ])
                } header: {
                    Text("Outside Air (IFE)")
                } footer: {
                    if output.outsideAir.staticAirTemperature.source == .unavailable {
                        Text(
                            "No in-flight-entertainment endpoint found yet — best-effort, "
                            + "and often unavailable."
                        )
                    }
                }

                Section {
                    NavigationLink {
                        TurbulenceSurface()
                    } label: {
                        FeatureCard(
                            title: "Turbulence", subtitle: turbulenceSubtitle(output),
                            systemImage: "waveform.path.ecg", signal: turbulenceSignal(output)
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FixQualitySurface()
                    } label: {
                        FeatureCard(
                            title: "Fix Quality", subtitle: fixQualitySubtitle(output),
                            systemImage: "location", signal: fixSignal(output)
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StatisticsSurface()
                    } label: {
                        FeatureCard(
                            title: "Statistics", subtitle: "Mean, min/max, and percentiles over a window",
                            systemImage: "chart.bar", signal: ContrailSignal.cyan
                        )
                    }
                    .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.horizontal)
                .padding(.vertical, 4)

                Section("Route") {
                    if let progress = output.route.fractionalProgress.value {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Progress")
                                Spacer()
                                Text("\(Int((progress * 100).rounded()))%")
                                    .font(.instrumentValue(15))
                            }
                            ProgressView(value: progress)
                                .tint(ContrailSignal.cyan)
                        }
                    }
                    if let city = output.route.nearestCity.value {
                        LabeledContent("Nearest city") {
                            Text("\(Int(city.distance / 1609.34)) mi, \(Int(city.bearing))° — \(city.name)")
                        }
                    }
                    if let eta = output.route.eta.value {
                        LabeledContent("ETA") {
                            Text(eta.arrival, style: .relative)
                                + Text(eta.scheduleDelta < 0 ? " ahead of schedule" : " behind schedule")
                        }
                    }
                    LabeledContent("Flight phase") {
                        Text(output.phase.value?.rawValue.capitalized ?? "—")
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Flight Active",
                    systemImage: "gauge.with.dots.needle.67percent",
                    description: Text("Start a flight from the Flight tab to see live instruments.")
                )
            }
        }
        .navigationTitle("Instruments")
    }

    @ViewBuilder
    private func tileGrid(_ tiles: [InstrumentTile]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in tile }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .padding(.horizontal)
    }

    private func turbulenceSubtitle(_ output: EstimatorOutput) -> String {
        guard let edr = output.turbulence.edrCubeRoot.value else { return "Not measuring yet" }
        return "\(TurbulenceCategory(edrCubeRoot: edr).rawValue) — \(String(format: "%.2f", edr)) m^(2/3)/s"
    }

    private func turbulenceSignal(_ output: EstimatorOutput) -> Color {
        guard let edr = output.turbulence.edrCubeRoot.value else { return .secondary }
        return ContrailSignal.forTurbulence(TurbulenceCategory(edrCubeRoot: edr))
    }

    private func fixQualitySubtitle(_ output: EstimatorOutput) -> String {
        switch output.position.fused.source {
        case .fused, .gnss: return "Live GNSS fix"
        case .deadReckoned: return "Dead reckoning — no recent fix"
        default: return "No position data yet"
        }
    }

    private func fixSignal(_ output: EstimatorOutput) -> Color {
        switch output.position.fused.source {
        case .fused, .gnss: return ContrailSignal.green
        case .deadReckoned: return ContrailSignal.amber
        default: return .secondary
        }
    }

    // MARK: - SI -> aviation-familiar unit conversions (display layer only; the log
    // and every export stay SI, per §6's own units convention).

    private func knots(_ metresPerSecond: Double?) -> Double? { metresPerSecond.map { $0 * 1.943844 } }
    private func feet(_ metres: Double?) -> Double? { metres.map { $0 * 3.28084 } }
    private func fpm(_ metresPerSecond: Double?) -> Double? { metresPerSecond.map { $0 * 196.850 } }

    private func fmt(_ value: Double?) -> String? { value.map { String(format: "%.0f", $0) } }
    private func fmtSigned(_ value: Double?) -> String? { value.map { String(format: "%+.0f", $0) } }
}
