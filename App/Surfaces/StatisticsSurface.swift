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
                HStack(alignment: .firstTextBaseline) {
                    Text("Mean")
                        .font(.instrumentLabel())
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(stats.mean.map { String(format: format, $0) } ?? "—")
                            .font(.instrumentValue(22))
                        Text(unit)
                            .font(.instrumentLabel(12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("MIN", stats.min, format: format)
                        chip("MAX", stats.max, format: format)
                        chip("σ", stats.standardDeviation, format: format)
                        chip("P50", stats.p50, format: format)
                        chip("P95", stats.p95, format: format)
                        chip("P99", stats.p99, format: format)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))

                LabeledContent("Samples") { Text("\(stats.sampleCount)").font(.instrumentValue(14)) }
            }
        }
    }

    @ViewBuilder
    private func chip(_ label: String, _ value: Double?, format: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.instrumentLabel(9))
                .foregroundStyle(.secondary)
            Text(value.map { String(format: format, $0) } ?? "—")
                .font(.instrumentValue(13, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
