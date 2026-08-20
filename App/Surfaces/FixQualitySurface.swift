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
                    LabeledContent("Currently displaying") {
                        sourceLabel(position.fused.source)
                    }
                    if let age = position.timeSinceValidFix.value {
                        LabeledContent("Time since valid fix") {
                            Text(String(format: "%.0f s", age))
                                .foregroundStyle(age > 10 ? .orange : .primary)
                        }
                    }
                }

                Section("Accuracy") {
                    LabeledContent("Horizontal") {
                        Text(position.horizontalAccuracy.value.map { String(format: "%.0f m", $0) } ?? "—")
                    }
                    LabeledContent("Vertical") {
                        Text(position.verticalAccuracy.value.map { String(format: "%.0f m", $0) } ?? "—")
                    }
                    LabeledContent("Confidence radius") {
                        Text(position.confidenceRadius.value.map { String(format: "%.0f m", $0) } ?? "—")
                    }
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
                .foregroundStyle(.green)
        case .deadReckoned:
            Label("Dead reckoned", systemImage: "location.slash.fill")
                .foregroundStyle(.orange)
        default:
            Text("—")
        }
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
