import Foundation
import ContrailCore
import ContrailGeo
import ContrailSensors
import ContrailEstimator
import ContrailTurbulence
import ContrailLog

/// Owns the (non-`Sendable`, single-writer-by-design) `Estimator` on its own
/// isolation domain, so it runs the ingestion loop off the main actor — matching the
/// plan's own concurrency note: "at 50 Hz an actor hop per sample is wasteful,"
/// which is exactly why the *whole loop* lives on one actor rather than hopping per
/// sample. Only throttled `EstimatorOutput` snapshots (`Sendable`) cross back out to
/// the UI, at roughly the plan's stated ~10 Hz.
///
/// Also owns `NDJSONLogWriter` directly, rather than bouncing decided-to-write
/// records out to a `@MainActor` owner: log writing is plain file I/O with no UI
/// involvement, so it belongs on the same actor that's already deciding *what* to
/// write via `AdaptiveLoggingController` (§3) — no cross-actor round-trip earns
/// anything here.
actor FlightEstimationEngine {
    private let estimator: Estimator
    private let source: any SensorSource
    private let uiUpdateInterval: TimeInterval
    /// Fed on *every* estimator output, at full sensor rate — §2.4's statistics
    /// engine needs the real sample stream, not the throttled UI snapshot. Only the
    /// computed `snapshot` (cheap: reading cached scalars out of each tracker's four
    /// windows, no rescanning) crosses out to the UI, and only at the throttled
    /// cadence alongside `onUpdate`.
    private let statistics = FlightStatisticsCollector()
    private let loggingController = AdaptiveLoggingController()
    private let logWriter: NDJSONLogWriter?

    init(
        flightPlan: FlightPlan,
        source: any SensorSource,
        nearestPlace: @escaping @Sendable (Coordinate) -> BearingToPlace? = { _ in nil },
        uiUpdateInterval: TimeInterval = 0.1,
        logWriter: NDJSONLogWriter?
    ) {
        self.estimator = Estimator(flightPlan: flightPlan, nearestPlace: nearestPlace)
        self.source = source
        self.uiUpdateInterval = uiUpdateInterval
        self.logWriter = logWriter
    }

    /// Runs until the underlying sensor stream ends or the calling task is
    /// cancelled. `onUpdate` fires at most once per `uiUpdateInterval`, even though
    /// `estimator.ingest`, the statistics collector, and the adaptive logging
    /// decision all run at full sensor rate underneath.
    ///
    /// `onUpdate` is `@MainActor`-isolated rather than a plain `@Sendable` closure
    /// bounced through a second `Task { @MainActor in }` at the call site — an
    /// isolated closure is the standard pattern for "an actor notifies a
    /// `@MainActor` observer": calling it here requires `await` (crossing into that
    /// actor), but its *captures* don't need to be `Sendable`, since the closure can
    /// only ever run on the actor it's isolated to. That sidesteps the awkward
    /// doubly-nested `Task { [weak self] in Task { @MainActor [weak self] in ... } }`
    /// this replaced, which fought the Swift 6 checker for no real benefit.
    ///
    /// `onLogError` fires whenever a write actually fails — rare, but the UI still
    /// needs to know (§5's "verified state, not a hopeful one" applies here too).
    func run(
        onUpdate: @escaping @MainActor @Sendable (EstimatorOutput, FlightStatisticsSnapshot) -> Void,
        onLogError: @escaping @MainActor @Sendable (String) -> Void
    ) async {
        // Runs regardless of *how* this function exits -- normal completion, or the
        // early `return` on cancellation below. `AppModel` only cancels the task and
        // never touches `logWriter` itself: two different isolation domains closing
        // the same non-Sendable writer concurrently would be a real race, since Task
        // cancellation is cooperative, not immediate -- there's no guarantee the
        // actor has actually stopped executing by the time `stopFlight()` returns.
        // This actor owns the writer's full lifecycle, start to finish.
        defer {
            try? logWriter?.flush()
            try? logWriter?.close()
        }

        var lastEmit = Date.distantPast
        var flushCounter = 0

        for await sample in source.samples() {
            if Task.isCancelled { return }
            guard let output = estimator.ingest(sample) else { continue }
            statistics.ingest(output)

            let toWrite = loggingController.decide(
                output: output, filteredVerticalAcceleration: estimator.latestFilteredVerticalAcceleration
            )
            for record in toWrite {
                do {
                    try logWriter?.append(LogRecord(output: record))
                    // §6: "batched fsync," not one per line -- flush periodically
                    // instead of on every append.
                    flushCounter += 1
                    if flushCounter >= 20 {
                        flushCounter = 0
                        try logWriter?.flush()
                    }
                } catch {
                    await onLogError("Log write failed: \(error)")
                }
            }

            let now = Date()
            guard now.timeIntervalSince(lastEmit) >= uiUpdateInterval else { continue }
            lastEmit = now
            await onUpdate(output, statistics.snapshot)
        }
    }
}
