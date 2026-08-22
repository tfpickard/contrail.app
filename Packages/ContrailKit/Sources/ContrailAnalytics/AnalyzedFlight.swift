import Foundation
import ContrailLog

/// ROADMAP Phase 4: "this phase writes no new sensor code -- it reads the
/// accumulated corpus." Every compiler in this package takes the same shape of
/// input: a decoded manifest plus its samples, exactly what `FlightLogStore`
/// already loads from `Documents/Flights/`. The App layer is responsible for
/// assembling this array; nothing here knows about the filesystem.
public struct AnalyzedFlight: Sendable {
    public let manifest: FlightManifest
    public let records: [LogRecord]

    public init(manifest: FlightManifest, records: [LogRecord]) {
        self.manifest = manifest
        self.records = records
    }

    /// Sample records only -- event/marker records don't carry the continuous
    /// channel values every compiler in this package works from.
    var samples: [LogRecord] { records.filter { $0.kind == .sample } }

    var routeKey: String { "\(manifest.flight.origin.icao)-\(manifest.flight.destination.icao)" }
}

/// Shared descriptive statistics over a pooled set of measured values -- every
/// "distribution" ROADMAP Phase 4 asks for (route turbulence, aircraft comparison,
/// seat comparison) reduces to this same shape, computed over whatever population
/// of samples a given compiler pools together.
public struct SampleDistribution: Sendable, Equatable {
    public let count: Int
    public let mean: Double
    public let min: Double
    public let max: Double
    public let standardDeviation: Double
    public let p50: Double
    public let p95: Double
    public let p99: Double

    /// `nil` for an empty population -- there is no honest distribution to report
    /// over zero samples, and a caller should treat that as "no data," not a
    /// zero-filled one.
    public static func compute(_ values: [Double]) -> SampleDistribution? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        let mean = sorted.reduce(0, +) / Double(count)
        let variance = sorted.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(count)
        return SampleDistribution(
            count: count,
            mean: mean,
            min: sorted[0],
            max: sorted[count - 1],
            standardDeviation: variance.squareRoot(),
            p50: percentile(sorted, 0.50),
            p95: percentile(sorted, 0.95),
            p99: percentile(sorted, 0.99)
        )
    }

    /// Nearest-rank percentile over an already-sorted array -- exact, not
    /// interpolated, which matches what §2.4's own windowed-statistics engine does
    /// elsewhere in this app (`ChannelStatisticsTracker`) for the same values at a
    /// shorter timescale.
    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        // `Swift.min`/`Swift.max`, not the bare global names -- inside this type,
        // unqualified `min`/`max` resolve to `SampleDistribution`'s own stored
        // properties of the same name before falling back to the free functions.
        let index = Swift.min(sorted.count - 1, Swift.max(0, Int((fraction * Double(sorted.count)).rounded(.up)) - 1))
        return sorted[index]
    }
}
