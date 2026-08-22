import SwiftUI
import ContrailCore

/// §2.2/§8's fix-quality panel — the honest position story: horizontal/vertical
/// accuracy, time since the last valid fix, and whether the app is currently
/// displaying a live GNSS fix or a dead-reckoned estimate. No satellite count, no
/// DOP — iOS exposes neither (§2.2's own stated limitation).
struct FixQualitySurface: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let position = model.latestOutput?.position {
                Section("Fix source") {
                    HStack {
                        sourceLabel(position.fused.source)
                        Spacer()
                        if let age = position.timeSinceValidFix.value {
                            Text(String(format: "%.0f s since fix", age))
                                .font(.instrumentValue(13, weight: .medium))
                                .foregroundStyle(age > 10 ? ContrailSignal.amber : .secondary)
                        }
                    }
                }

                Section("Accuracy") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        InstrumentTile(
                            label: "H ACC", value: position.horizontalAccuracy.value.map { String(format: "%.0f", $0) },
                            unit: "m", signal: accuracySignal(position.horizontalAccuracy.value)
                        )
                        InstrumentTile(
                            label: "V ACC", value: position.verticalAccuracy.value.map { String(format: "%.0f", $0) },
                            unit: "m", signal: accuracySignal(position.verticalAccuracy.value)
                        )
                        InstrumentTile(
                            label: "RADIUS", value: position.confidenceRadius.value.map { String(format: "%.0f", $0) },
                            unit: "m", signal: accuracySignal(position.confidenceRadius.value)
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.horizontal)
                }

                Section("Estimates") {
                    LabeledContent("GNSS fix") {
                        coordinateText(position.gnss.value)
                    }
                    LabeledContent("Dead-reckoned") {
                        coordinateText(position.deadReckoned.value)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Fix Data",
                    systemImage: "location.slash",
                    description: Text("Start a flight to see fix quality.")
                )
            }
        }
        .navigationTitle("Fix Quality")
    }

    @ViewBuilder
    private func sourceLabel(_ source: ChannelSource) -> some View {
        switch source {
        case .fused, .gnss:
            Label("Live GNSS", systemImage: "location.fill")
                .foregroundStyle(ContrailSignal.green)
        case .deadReckoned:
            Label("Dead reckoned", systemImage: "location.slash.fill")
                .foregroundStyle(ContrailSignal.amber)
        default:
            Text("—")
        }
    }

    private func accuracySignal(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        if value <= 15 { return ContrailSignal.green }
        if value <= 50 { return ContrailSignal.amber }
        return ContrailSignal.red
    }

    private func coordinateText(_ coordinate: Coordinate?) -> some View {
        Group {
            if let coordinate {
                Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
            } else {
                Text("—")
            }
        }
    }
}
