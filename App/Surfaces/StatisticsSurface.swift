import SwiftUI
import ContrailStatistics

/// §8: "a metrics surface exposing every channel... with window selection." Unlike
/// `MetricsSurface` (instantaneous values only, per 1.0's original scope),
/// this is 1.1's windowed view: mean/min/max/stddev/percentiles over the selected
/// window, for the channel set `FlightStatisticsCollector` tracks.
struct StatisticsSurface: View {
    @Environment(AppModel.self) private var model
    @State private var selectedWindow: StatisticsWindow = .oneMinute

    var body: some View {
        List {
            if let snapshot = model.latestStatistics {
                Section {
                    Picker("Window", selection: $selectedWindow) {
                        ForEach(StatisticsWindow.allCases, id: \.self) { window in
                            Text(label(for: window)).tag(window)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowInsets(EdgeInsets())
                .padding(.horizontal)

                channelSection("Groundspeed", unit: "m/s", format: "%.1f", snapshot.groundspeed)
                channelSection("Vertical speed", unit: "m/s", format: "%.2f", snapshot.verticalSpeed)
                channelSection("Cross-track error", unit: "m", format: "%.0f", snapshot.crossTrackError)
                channelSection("Cabin pressure altitude", unit: "m", format: "%.0f", snapshot.cabinPressureAltitude)
                channelSection("Pressurization rate", unit: "m/s", format: "%.2f", snapshot.pressurizationRate)
            } else {
                ContentUnavailableView(
                    "No Statistics Yet",
                    systemImage: "chart.bar",
                    description: Text("Start a flight to begin collecting windowed statistics.")
                )
            }
        }
        .navigationTitle("Statistics")
    }

    private func label(for window: StatisticsWindow) -> String {
        switch window {
        case .oneMinute: return "1 min"
        case .fiveMinutes: return "5 min"
        case .thirtyMinutes: return "30 min"
        case .wholeFlight: return "Flight"
        }
    }

    @ViewBuilder
    private func channelSection(_ name: String, unit: String, format: String, _ all: AllWindowStatistics) -> some View {
        let stats = all[selectedWindow]
        Section(name) {
            if stats.sampleCount == 0 {
                Text("No samples yet").foregroundStyle(.secondary)
            } else {
                statRow("Mean", stats.mean, unit: unit, format: format)
                statRow("Min", stats.min, unit: unit, format: format)
                statRow("Max", stats.max, unit: unit, format: format)
                statRow("Std dev", stats.standardDeviation, unit: unit, format: format)
                statRow("p50", stats.p50, unit: unit, format: format)
                statRow("p95", stats.p95, unit: unit, format: format)
                statRow("p99", stats.p99, unit: unit, format: format)
                LabeledContent("Samples") { Text("\(stats.sampleCount)") }
            }
        }
    }

    @ViewBuilder
    private func statRow(_ name: String, _ value: Double?, unit: String, format: String) -> some View {
        LabeledContent(name) {
            if let value {
                Text(String(format: "\(format) \(unit)", value))
            } else {
                Text("—")
            }
        }
    }
}
