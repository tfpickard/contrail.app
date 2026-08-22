/// The NDJSON log schema version. Written on every sample line (see ContrailLog), so a
/// file remains parseable even if the schema drifts mid-flight.
///
/// Phase 1.0 ships `{1, 0}`. Bump `minor` for additive changes (new optional field);
/// bump `major` only for a breaking change to an existing field's meaning or type.
public struct SchemaVersion: Sendable, Codable, Equatable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// {1,1} adds `EstimatorOutput.outsideAir` (Phase 3b) -- additive, so every
    /// {1,0} log line still parses; `outsideAir` was already `.unavailable`-shaped
    /// for anything reading an older file that never wrote the key.
    public static let current = SchemaVersion(major: 1, minor: 1)
}
