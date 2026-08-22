import Foundation

/// ROADMAP 3b: "build it as a pluggable prober: try a set of known endpoints, sniff
/// the payload shape, adapt." `fetch` is injected rather than this type owning a
/// `URLSession` directly -- same reasoning as `Estimator`'s `nearestPlace`/
/// `forecastLookup` closures: the App layer decides how (and with what timeout) a
/// request actually happens, and this stays testable with no real network.
public struct IFEProber: Sendable {
    private let targets: [IFEProbeTarget]
    private let parsers: [any IFEPayloadParser]
    private let fetch: @Sendable (IFEProbeTarget) async throws -> Data

    public init(
        targets: [IFEProbeTarget] = IFEProbeTarget.knownTargets,
        parsers: [any IFEPayloadParser] = [GenericKeySniffingParser()],
        fetch: @escaping @Sendable (IFEProbeTarget) async throws -> Data
    ) {
        self.targets = targets
        self.parsers = parsers
        self.fetch = fetch
    }

    /// Tries every target in order, returning the first reading any parser makes
    /// sense of. A target whose fetch throws (timeout, connection refused, TLS
    /// error) or whose response no parser recognizes is silently skipped -- ROADMAP
    /// 3b's "failure costs nothing" applies per-target, not just to the probe as a
    /// whole, since most targets on most flights will simply not exist.
    public func probe() async -> IFEReading? {
        for target in targets {
            guard let data = try? await fetch(target) else { continue }
            for parser in parsers {
                if let reading = parser.parse(data) {
                    return reading
                }
            }
        }
        return nil
    }
}
