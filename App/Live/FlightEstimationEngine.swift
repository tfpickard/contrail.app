import Foundation
import ContrailCore
import ContrailGeo
import ContrailSensors
import ContrailEstimator

/// Owns the (non-`Sendable`, single-writer-by-design) `Estimator` on its own
/// isolation domain, so it runs the ingestion loop off the main actor — matching the
/// plan's own concurrency note: "at 50 Hz an actor hop per sample is wasteful,"
/// which is exactly why the *whole loop* lives on one actor rather than hopping per
/// sample. Only throttled `EstimatorOutput` snapshots (`Sendable`) cross back out to
/// the UI, at roughly the plan's stated ~10 Hz.
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

    init(
        flightPlan: FlightPlan,
        source: any SensorSource,
        nearestPlace: @escaping @Sendable (Coordinate) -> BearingToPlace? = { _ in nil },
        uiUpdateInterval: TimeInterval = 0.1
    ) {
        self.estimator = Estimator(flightPlan: flightPlan, nearestPlace: nearestPlace)
        self.source = source
        self.uiUpdateInterval = uiUpdateInterval
    }

    /// Runs until the underlying sensor stream ends or the calling task is
    /// cancelled. `onUpdate` fires at most once per `uiUpdateInterval`, even though
    /// `estimator.ingest` (and the statistics collector) run at full sensor rate
    /// underneath.
    ///
    /// `onUpdate` is `@MainActor`-isolated rather than a plain `@Sendable` closure
    /// bounced through a second `Task { @MainActor in }` at the call site — an
    /// isolated closure is the standard pattern for "an actor notifies a
    /// `@MainActor` observer": calling it here requires `await` (crossing into that
    /// actor), but its *captures* don't need to be `Sendable`, since the closure can
    /// only ever run on the actor it's isolated to. That sidesteps the awkward
    /// doubly-nested `Task { [weak self] in Task { @MainActor [weak self] in ... } }`
    /// this replaced, which fought the Swift 6 checker for no real benefit.
    func run(onUpdate: @escaping @MainActor @Sendable (EstimatorOutput, FlightStatisticsSnapshot) -> Void) async {
        var lastEmit = Date.distantPast
        for await sample in source.samples() {
            if Task.isCancelled { return }
            guard let output = estimator.ingest(sample) else { continue }
            statistics.ingest(output)

            let now = Date()
            guard now.timeIntervalSince(lastEmit) >= uiUpdateInterval else { continue }
            lastEmit = now
            await onUpdate(output, statistics.snapshot)
        }
    }
}
