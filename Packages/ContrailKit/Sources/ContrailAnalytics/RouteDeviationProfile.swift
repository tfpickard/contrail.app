import Foundation

/// ROADMAP Phase 4: "Route deviation patterns. Cross-track history reveals where
/// reroutes reliably happen." Buckets every flight sharing a route by along-track
/// distance from the origin, pooling `crossTrackError` within each bucket across
/// every flight -- a bucket with an unusually large mean or max absolute deviation
/// is a place this route reliably gets rerouted, not just where one flight happened
/// to drift.
public struct RouteDeviationBucket: Sendable, Equatable, Identifiable {
    public var id: Double { alongTrackStartMetres }
    public let alongTrackStartMetres: Double
    /// Signed mean -- a consistent sign across flights (not just a large
    /// magnitude) means this route is reliably routed to one side here, not just
    /// noisily scattered.
    public let meanCrossTrackErrorMetres: Double
    public let maxAbsoluteCrossTrackErrorMetres: Double
    public let sampleCount: Int

    public init(
        alongTrackStartMetres: Double, meanCrossTrackErrorMetres: Double,
        maxAbsoluteCrossTrackErrorMetres: Double, sampleCount: Int
    ) {
        self.alongTrackStartMetres = alongTrackStartMetres
        self.meanCrossTrackErrorMetres = meanCrossTrackErrorMetres
        self.maxAbsoluteCrossTrackErrorMetres = maxAbsoluteCrossTrackErrorMetres
        self.sampleCount = sampleCount
    }
}

public enum RouteDeviationCompiler {
    /// `route` must match `AnalyzedFlight.routeKey` (`"ICAO-ICAO"`) -- computed per
    /// route, not for the whole corpus at once, since along-track distance is only
    /// comparable between flights that flew the same route.
    public static func compile(
        for route: String, from flights: [AnalyzedFlight], bucketMetres: Double = 20_000
    ) -> [RouteDeviationBucket] {
        guard bucketMetres > 0 else { return [] }
        var byBucket: [Int: [Double]] = [:]

        for flight in flights where flight.routeKey == route {
            for sample in flight.samples {
                guard let alongTrack = sample.route.alongTrackFlown.value,
                      let crossTrack = sample.route.crossTrackError.value else { continue }
                let bucketIndex = Int((alongTrack / bucketMetres).rounded(.down))
                byBucket[bucketIndex, default: []].append(crossTrack)
            }
        }

        return byBucket.keys.sorted().compactMap { index in
            guard let values = byBucket[index], !values.isEmpty else { return nil }
            let mean = values.reduce(0, +) / Double(values.count)
            let maxAbsolute = values.map { abs($0) }.max() ?? 0
            return RouteDeviationBucket(
                alongTrackStartMetres: Double(index) * bucketMetres,
                meanCrossTrackErrorMetres: mean,
                maxAbsoluteCrossTrackErrorMetres: maxAbsolute,
                sampleCount: values.count
            )
        }
    }
}
