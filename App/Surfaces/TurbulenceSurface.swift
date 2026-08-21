import SwiftUI
import ContrailCore

/// §4.1's turbulence view. "Be honest in the UI about what is being measured...
/// present this as a calibrated-relative intensity trace, with the absolute-scale
/// caveat stated in the interface, not buried" — that caveat is the whole point of
/// this surface's header, not an afterthought.
struct TurbulenceSurface: View {
    @Environment(AppModel.self) private var model

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
                Section("Measured") {
                    LabeledContent("EDR^(1/3)") {
                        if let edr = turbulence.edrCubeRoot.value {
                            Text(String(format: "%.3f m^(2/3)/s", edr))
                        } else {
                            Text("—")
                        }
                    }
                    LabeledContent("Category") {
                        Text(category(forEDR: turbulence.edrCubeRoot.value))
                    }
                    LabeledContent("Attitude gate") {
                        gateLabel(turbulence.attitudeGateOpen.value)
                    }
                }

                Section("Forecast") {
                    // 1.6's job -- always unavailable until the GTG comparison
                    // lands, per the schema's own from-day-one nullable field.
                    LabeledContent("GTG EDR^(1/3)") { Text("Not available") }
                        .foregroundStyle(.secondary)
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
    }

    private func category(forEDR edr: Double?) -> String {
        guard let edr else { return "—" }
        return TurbulenceCategory(edrCubeRoot: edr).rawValue
    }

    @ViewBuilder
    private func gateLabel(_ isOpen: Bool?) -> some View {
        switch isOpen {
        case true:
            Label("Stable", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case false:
            Label("Handling motion", systemImage: "hand.raised.fill").foregroundStyle(.orange)
        case nil:
            Text("—")
        }
    }
}
