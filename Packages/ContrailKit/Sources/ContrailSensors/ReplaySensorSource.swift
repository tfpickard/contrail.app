import Foundation

/// §2.2: "plays back a recorded flight log file at configurable speed, including
/// faster-than-realtime. The replay source is not optional and is not a testing
/// nicety. Dead reckoning, turbulence estimation, and phase classification cannot be
/// developed or verified without it."
///
/// A `struct` rather than an `actor` — every stored property is an immutable `let`,
/// so there is no shared mutable state to isolate; each call to `samples()` starts an
/// independent playback of the same underlying log.
public struct ReplaySensorSource: SensorSource {
    private let orderedSamples: [RawSensorSample]
    /// 1.0 = real time, 20.0 = 20x faster than real time, etc. Values `<= 0` are
    /// treated as `1.0`.
    public let speedMultiplier: Double

    /// Replays an in-memory sequence of samples — the primary path for tests, and for
    /// `SyntheticFlightLog`-generated demo flights. Samples are sorted by timestamp
    /// on init so the caller does not have to pre-sort.
    public init(samples: [RawSensorSample], speedMultiplier: Double = 1.0) {
        self.orderedSamples = samples.sorted { $0.timestamp < $1.timestamp }
        self.speedMultiplier = speedMultiplier > 0 ? speedMultiplier : 1.0
    }

    /// Replays a recorded log from disk: NDJSON, one `RawSensorSample` per line —
    /// the format a bundled on-device sample log (§2.2) ships as.
    public init(contentsOf url: URL, speedMultiplier: Double = 1.0) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        let samples: [RawSensorSample] = try text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                try decoder.decode(RawSensorSample.self, from: Data(line.utf8))
            }
        self.init(samples: samples, speedMultiplier: speedMultiplier)
    }

    public func samples() -> AsyncStream<RawSensorSample> {
        let orderedSamples = self.orderedSamples
        let speedMultiplier = self.speedMultiplier

        return AsyncStream { continuation in
            let task = Task {
                var previousTimestamp: Date?
                for sample in orderedSamples {
                    if Task.isCancelled { break }
                    if let previous = previousTimestamp {
                        let delta = sample.timestamp.timeIntervalSince(previous)
                        if delta > 0 {
                            let sleepSeconds = delta / speedMultiplier
                            let nanoseconds = UInt64(max(0, sleepSeconds) * 1_000_000_000)
                            try? await Task.sleep(nanoseconds: nanoseconds)
                        }
                    }
                    continuation.yield(sample)
                    previousTimestamp = sample.timestamp
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    /// `.iso8601` alone rejects fractional seconds, which every timestamp in this
    /// app carries.
    static var iso8601WithFractionalSeconds: JSONDecoder.DateDecodingStrategy {
        // A fresh formatter per call, deliberately not captured — ISO8601DateFormatter
        // is a mutable class and not Sendable, so sharing one instance across this
        // @Sendable decoding closure would be a real (if narrow) data race under
        // concurrent decode calls.
        .custom { decoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date with fractional seconds: \(string)"
                )
            }
            return date
        }
    }
}
