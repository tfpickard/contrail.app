import Foundation
import ContrailCore
import ContrailData

/// ROADMAP Phase 4's personal-statistics bullet: "airspace crossed." Nothing in the
/// log records which ARTCC a position falls in -- that's computed live in the App
/// layer (`RouteIntelligenceEngine.currentARTCC`) and never persisted -- but it's
/// fully recoverable after the fact from the corpus plus the same bundled ARTCC
/// boundary dataset the live lookup already uses, since every sample already
/// carries a position. No new sensor data needed, exactly what "reads the
/// accumulated corpus" promises.
public enum AirspaceHistoryCompiler {
    /// Same 18,000 ft MSL high/low threshold `RouteIntelligenceEngine` uses live,
    /// kept here as its own named constant rather than a bare literal so the two
    /// call sites can't silently drift apart.
    public static let highLowThresholdMetres = 5_486.4

    /// Every sample's position is a point-in-polygon test against up to several
    /// dozen boundaries -- real cost across a whole corpus, not free. `sampleStride`
    /// checks every Nth sample instead of all of them: ARTCC boundaries are large
    /// relative to how far an airliner moves between consecutive samples, so this
    /// answers "was this airspace ever crossed," not "at what exact instant,"
    /// without materially risking missing a genuine crossing.
    public static func compile(
        from flights: [AnalyzedFlight], artccIndex: ARTCCBoundaryIndex, sampleStride: Int = 10
    ) -> [ARTCCBoundary] {
        var seenByID: [String: ARTCCBoundary] = [:]

        for flight in flights {
            let samples = flight.samples
            var index = 0
            while index < samples.count {
                defer { index += sampleStride }
                let sample = samples[index]
                guard let position = sample.position.fused.value else { continue }
                let altitude = sample.position.altitudeGPS.value ?? 0
                let tier: ARTCCBoundary.AltitudeTier = altitude >= highLowThresholdMetres ? .high : .low
                if let boundary = artccIndex.boundary(containing: position, tier: tier) {
                    seenByID[boundary.id] = boundary
                }
            }
        }

        return seenByID.values.sorted { $0.id < $1.id }
    }
}
