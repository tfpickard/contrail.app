import SwiftUI
import Charts
import ContrailCore

/// §4.1's turbulence view — the app's one marquee, checked-obsessively feature, and
/// its signature screen: a live oscilloscope-style tape rather than a generic
/// rounded-corner chart, because that's what the feeling actually is -- watching a
/// real instrument, not a dashboard widget. "Be honest in the UI about what is
/// being measured... present this as a calibrated-relative intensity trace, with
/// the absolute-scale caveat stated in the interface, not buried" -- that caveat is
/// the whole point of this surface's header, not an afterthought.
struct TurbulenceSurface: View {
    @Environment(AppModel.self) private var model
    @State private var history: [TurbulenceSample] = []

    var body: some View {
        List {
            Section {
                Label {
                    Text(
                        "This is a calibrated-relative intensity trace, not an "
                        + "airframe-calibrated measurement. The sensor is on a tray "
                        + "table or in a lap, not bolted to the aircraft — there's "
                        + "an unknown transfer function in between."
                    )
                    .font(.footnote)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(.secondary)
            }

            if let turbulence = model.latestOutput?.turbulence {
                Section {
                    tapeView
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 6)
                } header: {
                    HStack {
                        Text("Live Trace")
                        Spacer()
                        categoryBadge(turbulence.edrCubeRoot.value)
                    }
                }

                Section("Measured") {
                    HStack(spacing: 10) {
                        InstrumentTile(
                            label: "EDR^(1/3)",
                            value: turbulence.edrCubeRoot.value.map { String(format: "%.2f", $0) },
                            unit: "m^(2/3)/s",
                            signal: currentSignal(turbulence.edrCubeRoot.value)
                        )
                        InstrumentTile(
                            label: "Handling",
                            value: gateText(turbulence.attitudeGateOpen.value),
                            unit: nil,
                            signal: turbulence.attitudeGateOpen.value == false ? ContrailSignal.amber : ContrailSignal.green
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.horizontal)
                }

                Section {
                    LabeledContent("GTG EDR^(1/3)") {
                        if let forecast = turbulence.forecastEdrCubeRoot.value {
                            Text(String(format: "%.3f m^(2/3)/s", forecast))
                        } else {
                            Text("Not available")
                        }
                    }
                    if let measured = turbulence.edrCubeRoot.value, let forecast = turbulence.forecastEdrCubeRoot.value {
                        // §4.3: "the residual" -- positive means worse than forecast.
                        LabeledContent("Residual (measured − forecast)") {
                            Text(String(format: "%+.3f m^(2/3)/s", measured - forecast))
                        }
                    }
                } header: {
                    Text("Forecast")
                } footer: {
                    if turbulence.forecastEdrCubeRoot.value == nil {
                        Text("Enter a GribStream API token on the Flight tab before starting to compare against NOAA's GTG forecast.")
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Turbulence Data",
                    systemImage: "waveform.path.ecg",
                    description: Text("Start a flight to begin measuring.")
                )
            }
        }
        .navigationTitle("Turbulence")
        .onChange(of: model.latestOutput) { _, newOutput in
            recordSample(newOutput)
        }
    }

    private func recordSample(_ output: EstimatorOutput?) {
        guard let output, let edr = output.turbulence.edrCubeRoot.value else { return }
        history.append(TurbulenceSample(date: output.t, value: edr))
        let cutoff = output.t.addingTimeInterval(-5 * 60)
        history.removeAll { $0.date < cutoff }
        if history.count > 600 { history.removeFirst(history.count - 600) }
    }

    /// The signature element: a dark instrument-tape strip regardless of the
    /// system's light/dark setting, the same way a camera viewfinder or an
    /// oscilloscope screen doesn't follow the room's lighting -- this is meant to
    /// read as a physical instrument, not a themed chart.
    @ViewBuilder
    private var tapeView: some View {
        let tapeColor = currentSignal(history.last?.value)
        let upperBound = max(1.0, (history.map(\.value).max() ?? 0) * 1.15)

        Group {
            if history.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.3))
                    Text("Trace begins once turbulence is measured.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart {
                    ForEach(history) { sample in
                        AreaMark(x: .value("Time", sample.date), y: .value("EDR", sample.value))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [tapeColor.opacity(0.35), .clear],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        LineMark(x: .value("Time", sample.date), y: .value("EDR", sample.value))
                            .foregroundStyle(tapeColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                    RuleMark(y: .value("Moderate", 0.4))
                        .foregroundStyle(ContrailSignal.amber.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                .chartYScale(domain: 0...upperBound)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(minHeight: 150)
            }
        }
        .padding(12)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal)
        .animation(.easeOut(duration: 0.4), value: history.last?.value)
    }

    @ViewBuilder
    private func categoryBadge(_ edr: Double?) -> some View {
        let category = edr.map(TurbulenceCategory.init)
        Text(category?.rawValue ?? "—")
            .font(.instrumentLabel(12))
            .foregroundStyle(category.map { ContrailSignal.forTurbulence($0) } ?? .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                (category.map { ContrailSignal.forTurbulence($0) } ?? .secondary).opacity(0.15),
                in: Capsule()
            )
    }

    private func currentSignal(_ edr: Double?) -> Color {
        guard let edr else { return .secondary }
        return ContrailSignal.forTurbulence(TurbulenceCategory(edrCubeRoot: edr))
    }

    private func gateText(_ isOpen: Bool?) -> String? {
        switch isOpen {
        case true: return "Stable"
        case false: return "Moving"
        case nil: return nil
        }
    }
}

private struct TurbulenceSample: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}
