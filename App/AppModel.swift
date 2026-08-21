import Foundation
import ContrailCore
import ContrailGeo
import ContrailData
import ContrailLog

/// The app's single source of UI-facing state. Owns pre-flight asset verification,
/// the active flight's `FlightPlan` and live `EstimatorOutput` stream, and the NDJSON
/// log for the current flight. Everything expensive (sensor ingestion, estimation)
/// happens off this actor via `FlightEstimationEngine`; this type only ever holds the
/// throttled, `Sendable` result.
@MainActor
@Observable
final class AppModel {
    enum AssetStatus: Equatable {
        case pending
        case verified(recordCount: Int)
        case failed(String)
    }

    // MARK: - Pre-flight readiness (§5: "per-asset verified state, not a hopeful one")

    private(set) var airportAssetStatus: AssetStatus = .pending
    private(set) var placeAssetStatus: AssetStatus = .pending

    private var airportIndex: AirportIndex?
    private var placeIndex: PlaceIndex?

    // MARK: - Active flight

    private(set) var flightPlan: FlightPlan?
    private(set) var latestOutput: EstimatorOutput?
    private(set) var latestStatistics: FlightStatisticsSnapshot?
    private(set) var isFlightActive = false
    private(set) var lastLogError: String?

    private var engine: FlightEstimationEngine?
    private var runTask: Task<Void, Never>?

    // MARK: - Offline basemap (§5.2)

    /// The XYZ tile URL template MapSurface's style JSON points at, once the local
    /// PMTiles-serving HTTP server is up. `nil` until `startMapServer()` completes --
    /// MapSurface shows a loading state rather than pointing MapLibre at a dead port.
    private(set) var mapTileURLTemplate: String?
    private var mapServer: PMTilesHTTPServer?

    /// Starts the loopback-only HTTP server that serves the bundled PMTiles basemap
    /// (see `PMTilesHTTPServer`'s own doc comment for why this exists instead of the
    /// `pmtiles://` custom URL scheme). Called once at launch, same as
    /// `verifyBundledAssets()` -- this is itself a bundled-asset verification: if the
    /// file is missing or the server can't bind loopback, the map surface reports that
    /// honestly instead of showing a blank tile grid.
    func startMapServer() async {
        do {
            let url = try BundledDatasets.basemapURL()
            let server = try PMTilesHTTPServer(pmtilesFileURL: url)
            try await server.start()
            guard let port = await server.port else {
                lastLogError = "Map server started but reported no port."
                return
            }
            mapServer = server
            mapTileURLTemplate = "http://127.0.0.1:\(port)/tiles/{z}/{x}/{y}.pbf"
        } catch {
            lastLogError = "Could not start the offline basemap server: \(error)"
        }
    }

    /// Loads and verifies the bundled datasets. Called once at launch — the
    /// pre-flight screen reads `airportAssetStatus`/`placeAssetStatus` directly
    /// rather than re-triggering verification itself.
    func verifyBundledAssets() {
        do {
            let index = try BundledDatasets.loadAirportIndex()
            airportIndex = index
            airportAssetStatus = .verified(recordCount: index.count)
        } catch {
            airportAssetStatus = .failed(String(describing: error))
        }

        do {
            let index = try BundledDatasets.loadPlaceIndex()
            placeIndex = index
            placeAssetStatus = .verified(recordCount: index.count)
        } catch {
            placeAssetStatus = .failed(String(describing: error))
        }
    }

    /// Resolves an ICAO code against the bundled airport index, for the pre-flight
    /// form's origin/destination fields.
    func airport(icao: String) -> AirportRecord? {
        airportIndex?.airport(icao: icao)
    }

    func startFlight(_ plan: FlightPlan) {
        stopFlight()

        flightPlan = plan
        isFlightActive = true
        lastLogError = nil

        let noPlaceLookup: @Sendable (Coordinate) -> BearingToPlace? = { _ in nil }
        let nearestPlace = placeIndex?.nearestPlaceLookup() ?? noPlaceLookup
        let source = LiveSensorSource()

        // Constructed here, handed off once, and never touched by AppModel again --
        // the engine owns its full lifecycle (see FlightEstimationEngine.run's own
        // doc comment on why two isolation domains must not share this instance).
        let writer = try? makeLogWriter(for: plan)
        if writer == nil {
            lastLogError = "Could not open a log file for this flight."
        }

        let engine = FlightEstimationEngine(
            flightPlan: plan, source: source, nearestPlace: nearestPlace, logWriter: writer
        )
        self.engine = engine

        runTask = Task {
            await engine.run(
                onUpdate: { [weak self] output, statistics in
                    self?.handle(output, statistics)
                },
                onLogError: { [weak self] message in
                    self?.lastLogError = message
                }
            )
        }
    }

    func stopFlight() {
        runTask?.cancel()
        runTask = nil
        engine = nil
        isFlightActive = false
    }

    private func handle(_ output: EstimatorOutput, _ statistics: FlightStatisticsSnapshot) {
        latestOutput = output
        latestStatistics = statistics
    }

    /// §6: one NDJSON file per flight, in the app's Documents directory. iCloud
    /// replication (§6's "local storage is the source of truth, iCloud is
    /// replication") is 1.0's own scope but not built in this pass — see the
    /// session's own deferral notes; local storage alone is still complete and
    /// crash-safe on its own.
    private func makeLogWriter(for plan: FlightPlan) throws -> NDJSONLogWriter {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let flightsDirectory = documents.appendingPathComponent("Flights", isDirectory: true)
        try FileManager.default.createDirectory(at: flightsDirectory, withIntermediateDirectories: true)

        let dateStamp = ISO8601DateFormatter().string(from: plan.scheduledDeparture).prefix(10)
        let flightID = "\(plan.flightNumber)-\(dateStamp)"
        let fileURL = flightsDirectory
            .appendingPathComponent(flightID, isDirectory: true)
            .appendingPathComponent("samples.ndjson")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        return try NDJSONLogWriter(fileURL: fileURL)
    }
}
