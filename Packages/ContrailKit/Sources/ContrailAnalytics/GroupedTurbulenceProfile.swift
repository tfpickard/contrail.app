import Foundation
import ContrailLog

/// ROADMAP Phase 4: "Aircraft and seat comparison. Ride quality by airframe type.
/// Whether your seat relative to the wing measurably changes what you feel --
/// which it does, and now you can prove it." Both comparisons are the same shape
/// (pool every measured sample by some grouping key, compute a distribution per
/// group), so one generic type and two thin key extractors cover both.
public struct GroupedTurbulenceProfile: Sendable, Equatable, Identifiable {
    public var id: String { group }
    public let group: String
    public let flightCount: Int
    public let distribution: SampleDistribution

    public init(group: String, flightCount: Int, distribution: SampleDistribution) {
        self.group = group
        self.flightCount = flightCount
        self.distribution = distribution
    }
}

/// Pools every measured sample by `key`, computing one `SampleDistribution` per
/// group. Flights where `key` returns `nil` are excluded entirely -- there's no
/// honest bucket for "unknown aircraft type" or "seat position not entered" that
/// wouldn't make that group's distribution meaningless.
private func groupTurbulence(
    _ flights: [AnalyzedFlight], key: (AnalyzedFlight) -> String?
) -> [GroupedTurbulenceProfile] {
    var byGroup: [String: (flightIDs: Set<String>, edrValues: [Double])] = [:]

    for flight in flights {
        guard let groupKey = key(flight) else { continue }
        var entry = byGroup[groupKey] ?? (flightIDs: [], edrValues: [])
        entry.flightIDs.insert(flight.manifest.flightID)
        entry.edrValues.append(contentsOf: flight.samples.compactMap { $0.turbulence.edrCubeRoot.value })
        byGroup[groupKey] = entry
    }

    return byGroup.compactMap { groupKey, entry in
        guard let distribution = SampleDistribution.compute(entry.edrValues) else { return nil }
        return GroupedTurbulenceProfile(group: groupKey, flightCount: entry.flightIDs.count, distribution: distribution)
    }.sorted { $0.group < $1.group }
}

public enum AircraftComparisonCompiler {
    public static func compile(from flights: [AnalyzedFlight]) -> [GroupedTurbulenceProfile] {
        groupTurbulence(flights) { $0.manifest.flight.aircraft.icaoType }
    }
}

public enum SeatComparisonCompiler {
    public static func compile(from flights: [AnalyzedFlight]) -> [GroupedTurbulenceProfile] {
        groupTurbulence(flights) { $0.manifest.flight.seatPosition?.displayName }
    }
}
