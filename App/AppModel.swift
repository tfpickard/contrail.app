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
    private var logWriter: NDJSONLogWriter?

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
        let engine = FlightEstimationEngine(flightPlan: plan, source: source, nearestPlace: nearestPlace)
        self.engine = engine

        logWriter = try? makeLogWriter(for: plan)
        if logWriter == nil {
            lastLogError = "Could not open a log file for this flight."
        }

        runTask = Task {
            await engine.run { [weak self] output, statistics in
                self?.handle(output, statistics)
            }
        }
    }

    func stopFlight() {
        runTask?.cancel()
        runTask = nil
        engine = nil
        try? logWriter?.flush()
        try? logWriter?.close()
        logWriter = nil
        isFlightActive = false
    }

    private func handle(_ output: EstimatorOutput, _ statistics: FlightStatisticsSnapshot) {
        latestOutput = output
        latestStatistics = statistics
        do {
            try logWriter?.append(LogRecord(output: output))
        } catch {
            lastLogError = "Log write failed: \(error)"
        }
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
