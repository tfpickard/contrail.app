import SwiftUI
import Charts
import ContrailCore
import ContrailLog
import ContrailData
import ContrailAnalytics

/// ROADMAP Phase 4 -- Meta-analysis: "what you learn from a hundred flights that
/// you cannot learn from one... this phase writes no new sensor code -- it reads
/// the accumulated corpus." Every section here is a `ContrailAnalytics` compiler
/// run fresh over everything `FlightLogStore` has on disk -- nothing is persisted
/// separately from the flights themselves, so this screen is always exactly as
/// current as the last flight logged.
struct InsightsSurface: View {
    @Environment(AppModel.self) private var model

    @State private var analyzedFlights: [AnalyzedFlight] = []
    @State private var routeStats: [RouteStatistics] = []
    @State private var forecastSkill: ForecastSkillScore?
    @State private var aircraftProfiles: [GroupedTurbulenceProfile] = []
    @State private var seatProfiles: [GroupedTurbulenceProfile] = []
    @State private var airspaceCrossed: [ARTCCBoundary] = []
    @State private var selectedDeviationRoute: String?
    @State private var deviationBuckets: [RouteDeviationBucket] = []

    var body: some View {
        List {
            if routeStats.isEmpty {
                ContentUnavailableView(
                    "Not Enough Data Yet", systemImage: "chart.xyaxis.line",
                    description: Text("Log a few flights to start seeing patterns across your history.")
                )
            } else {
                forecastSkillSection
                routeSection
                aircraftSection
                seatSection
                airspaceSection
                deviationSection
            }
        }
        .navigationTitle("Insights")
        .onAppear { refresh() }
        .refreshable { refresh() }
    }

    private func refresh() {
        let flights = FlightLogStore.listFlights().compactMap { summary -> AnalyzedFlight? in
            guard let manifest = summary.manifest,
                  let records = try? FlightLogStore.loadRecords(in: summary.directory) else { return nil }
            return AnalyzedFlight(manifest: manifest, records: records)
        }
        analyzedFlights = flights
        routeStats = RouteStatisticsCompiler.compile(from: flights)
        forecastSkill = ForecastSkillCompiler.compile(from: flights)
        aircraftProfiles = AircraftComparisonCompiler.compile(from: flights)
        seatProfiles = SeatComparisonCompiler.compile(from: flights)
        if let artccIndex = model.artccBoundaryIndex() {
            airspaceCrossed = AirspaceHistoryCompiler.compile(from: flights, artccIndex: artccIndex)
        }
        if selectedDeviationRoute == nil || !routeStats.contains(where: { $0.route == selectedDeviationRoute }) {
            selectedDeviationRoute = routeStats.max { $0.flightCount < $1.flightCount }?.route
        }
        updateDeviationBuckets()
    }

    private func updateDeviationBuckets() {
        guard let route = selectedDeviationRoute else {
            deviationBuckets = []
            return
        }
        deviationBuckets = RouteDeviationCompiler.compile(for: route, from: analyzedFlights)
    }

    @ViewBuilder
    private var forecastSkillSection: some View {
        Section {
            if let skill = forecastSkill {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    InstrumentTile(
                        label: "BIAS", value: String(format: "%+.2f", skill.bias), unit: nil,
                        signal: skill.bias <= 0 ? ContrailSignal.green : ContrailSignal.amber
                    )
                    InstrumentTile(
                        label: "MAE", value: String(format: "%.2f", skill.meanAbsoluteError), unit: nil,
                        signal: ContrailSignal.cyan
                    )
                    InstrumentTile(
                        label: "RMSE", value: String(format: "%.2f", skill.rootMeanSquareError), unit: nil,
                        signal: ContrailSignal.cyan
                    )
                    InstrumentTile(
                        label: "CORR", value: skill.correlation.map { String(format: "%.2f", $0) }, unit: nil,
                        signal: ContrailSignal.cyan
                    )
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.horizontal)
                Text("\(skill.pairedSampleCount) paired measured/forecast samples, across every flight that fetched GTG.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No flight has fetched a GTG forecast yet.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Forecast Skill")
        } footer: {
            Text(
                "Bias: positive means your flights measured rougher than GTG "
                + "predicted, on average, across everything you've logged."
            )
        }
    }

    @ViewBuilder
    private var routeSection: some View {
        Section("By Route") {
            ForEach(routeStats) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stat.route)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Spacer()
                        Text("\(stat.flightCount)×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let distribution = stat.distribution {
                        HStack(spacing: 14) {
                            Text("mean \(String(format: "%.2f", distribution.mean))")
                                .font(.instrumentValue(13))
                            Text("p95 \(String(format: "%.2f", distribution.p95))")
                                .font(.instrumentValue(13))
                                .foregroundStyle(.secondary)
                        }
                        if let roughest = roughestBucket(stat) {
                            Text(roughest).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No turbulence data yet").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func roughestBucket(_ stat: RouteStatistics) -> String? {
        guard let time = stat.byTimeOfDay.max(by: { $0.value < $1.value })?.key,
              let season = stat.bySeason.max(by: { $0.value < $1.value })?.key else { return nil }
        return "Roughest so far: \(time.rawValue.lowercased()) departures, \(season.rawValue.lowercased())"
    }

    @ViewBuilder
    private var aircraftSection: some View {
        if !aircraftProfiles.isEmpty {
            Section("By Aircraft") {
                ForEach(aircraftProfiles) { profile in groupRow(profile) }
            }
        }
    }

    @ViewBuilder
    private var seatSection: some View {
        if !seatProfiles.isEmpty {
            Section {
                ForEach(seatProfiles) { profile in groupRow(profile) }
            } header: {
                Text("By Seat")
            } footer: {
                Text("Only flights where you entered a seat position on the Flight tab count here.")
            }
        }
    }

    private func groupRow(_ profile: GroupedTurbulenceProfile) -> some View {
        HStack {
            Text(profile.group)
            Spacer()
            Text("\(profile.flightCount)× · mean \(String(format: "%.2f", profile.distribution.mean))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var airspaceSection: some View {
        if !airspaceCrossed.isEmpty {
            Section {
                ForEach(airspaceCrossed, id: \.id) { boundary in
                    LabeledContent(boundary.id, value: boundary.name.capitalized)
                }
            } header: {
                Text("Airspace Crossed")
            } footer: {
                Text(
                    "Recovered from your logged positions against the bundled ARTCC "
                    + "boundaries -- never logged directly."
                )
            }
        }
    }

    @ViewBuilder
    private var deviationSection: some View {
        Section {
            Picker(
                "Route",
                selection: Binding(
                    get: { selectedDeviationRoute },
                    set: { selectedDeviationRoute = $0; updateDeviationBuckets() }
                )
            ) {
                ForEach(routeStats) { stat in
                    Text(stat.route).tag(Optional(stat.route))
                }
            }

            if deviationBuckets.isEmpty {
                Text("Not enough route-relative data for this route yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Chart(deviationBuckets) { bucket in
                    BarMark(
                        x: .value("Along track (nm)", bucket.alongTrackStartMetres / 1852),
                        y: .value("Mean cross-track (m)", bucket.meanCrossTrackErrorMetres)
                    )
                    .foregroundStyle(
                        abs(bucket.meanCrossTrackErrorMetres) > 1_000 ? ContrailSignal.amber : ContrailSignal.cyan
                    )
                }
                .frame(height: 160)
                .padding(.top, 4)
            }
        } header: {
            Text("Route Deviation")
        } footer: {
            Text(
                "Mean cross-track error by distance along the route, pooled across "
                + "every flight -- a bar that stays large in one direction is where "
                + "this route reliably gets rerouted, not just scatter."
            )
        }
    }
}
