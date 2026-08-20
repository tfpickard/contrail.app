import SwiftUI
import ContrailCore

/// §8's instantaneous metrics surface — 1.1's windowed statistics (mean/min/max/
/// percentiles per window) are explicitly deferred; this shows the current value of
/// every channel §2.3 defines, honestly: an `.unavailable` channel reads "—", never
/// a fake zero (§9's whole reason `Channel` carries a `source` at all).
struct MetricsSurface: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            if let output = model.latestOutput {
                Section("Position") {
                    metric("Groundspeed", output.motion.groundspeed, unit: "m/s", format: "%.1f")
                    metric("True course", output.motion.trueCourse, unit: "°", format: "%.0f")
                    metric("Vertical speed", output.motion.verticalSpeed, unit: "m/s", format: "%.1f")
                    metric("Altitude (GPS)", output.position.altitudeGPS, unit: "m", format: "%.0f")
                    metric("Confidence radius", output.position.confidenceRadius, unit: "m", format: "%.0f")
                }

                Section("Cabin") {
                    metric("Pressure", output.cabin.pressure, unit: "kPa", format: "%.1f")
                    metric("Pressure altitude", output.cabin.pressureAltitude, unit: "m", format: "%.0f")
                    metric("Pressurization rate", output.cabin.pressurizationRate, unit: "m/s", format: "%.2f")
                }

                Section("Route") {
                    metric("Cross-track error", output.route.crossTrackError, unit: "m", format: "%.0f")
                    metric("Along-track flown", output.route.alongTrackFlown, unit: "m", format: "%.0f")
                    metric("Along-track remaining", output.route.alongTrackRemaining, unit: "m", format: "%.0f")
                    if let progress = output.route.fractionalProgress.value {
                        LabeledContent("Progress") { Text("\(Int(progress * 100))%") }
                    } else {
                        LabeledContent("Progress") { Text("—") }
                    }
                    if let city = output.route.nearestCity.value {
                        LabeledContent("Nearest city") {
                            Text("\(Int(city.distance / 1609.34)) mi, \(Int(city.bearing))° — \(city.name)")
                        }
                    } else {
                        LabeledContent("Nearest city") { Text("—") }
                    }
                    if let eta = output.route.eta.value {
                        LabeledContent("ETA") {
                            Text(eta.arrival, style: .relative)
                                + Text(eta.scheduleDelta < 0 ? " (ahead of schedule)" : " (behind schedule)")
                        }
                    } else {
                        LabeledContent("ETA") { Text("—") }
                    }
                }

                Section("Phase") {
                    LabeledContent("Flight phase") {
                        Text(output.phase.value?.rawValue.capitalized ?? "—")
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Flight Active",
                    systemImage: "airplane",
                    description: Text("Start a flight from the pre-flight screen.")
                )
            }
        }
        .navigationTitle("Metrics")
    }

    @ViewBuilder
    private func metric(_ name: String, _ channel: Channel<Double>, unit: String, format: String) -> some View {
        LabeledContent(name) {
            if let value = channel.value {
                Text(String(format: "\(format) \(unit)", value))
            } else {
                Text("—")
            }
        }
    }
}
