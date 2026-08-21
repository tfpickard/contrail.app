import Foundation
import ContrailLog

/// ROADMAP Phase 2's own framing of why the group flight record matters: "seated in
/// different places, genuinely different turbulence traces from the same airframe."
/// This turns a `GroupFlightRecord` into exactly that comparison -- each
/// participant's measured EDR^(1/3), aligned onto a shared time axis so they can be
/// read side by side, rather than left as N independent, unaligned sample streams.
public enum GroupTurbulenceComparison {
    /// One aligned instant: the bucket's start time, and each participant's mean
    /// EDR^(1/3) within that bucket, keyed by `participantName`. A participant
    /// absent from a bucket (no samples, or none with turbulence data) simply has
    /// no entry -- never a zero, per the same "absence, not a lie" principle
    /// `Channel` follows.
    public struct Point: Sendable, Equatable {
        public let bucketStart: Date
        public let values: [String: Double]

        public init(bucketStart: Date, values: [String: Double]) {
            self.bucketStart = bucketStart
            self.values = values
        }
    }

    /// Buckets every participant's turbulence samples into fixed-width windows and
    /// averages each participant's EDR^(1/3) within each window, producing one
    /// `Point` per bucket that has at least one participant's data. Bucket
    /// boundaries are anchored to the earliest sample across all participants, so
    /// two phones with slightly different sample cadences still land in the same
    /// buckets.
    public static func compare(_ record: GroupFlightRecord, bucketSeconds: TimeInterval = 30) -> [Point] {
        guard bucketSeconds > 0 else { return [] }

        let allTimestamps = record.participants.flatMap { participant in
            participant.records
                .filter { $0.kind == .sample && $0.turbulence.edrCubeRoot.value != nil }
                .map(\.t)
        }
        guard let anchor = allTimestamps.min() else { return [] }

        // bucketIndex -> participantName -> (sum, count)
        var buckets: [Int: [String: (sum: Double, count: Int)]] = [:]

        for participant in record.participants {
            for sample in participant.records where sample.kind == .sample {
                guard let edr = sample.turbulence.edrCubeRoot.value else { continue }
                let bucketIndex = Int((sample.t.timeIntervalSince(anchor) / bucketSeconds).rounded(.down))
                var byParticipant = buckets[bucketIndex] ?? [:]
                var entry = byParticipant[participant.participantName] ?? (sum: 0, count: 0)
                entry.sum += edr
                entry.count += 1
                byParticipant[participant.participantName] = entry
                buckets[bucketIndex] = byParticipant
            }
        }

        return buckets.keys.sorted().map { index in
            let byParticipant = buckets[index] ?? [:]
            let values = byParticipant.mapValues { $0.sum / Double($0.count) }
            let bucketStart = anchor.addingTimeInterval(Double(index) * bucketSeconds)
            return Point(bucketStart: bucketStart, values: values)
        }
    }
}
