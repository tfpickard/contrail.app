import Foundation
import ContrailCore
import ContrailGeo
import ContrailData

/// §5.3–§5.5: route intelligence built on the bundled FAA NASR datasets --
/// on-route fixes/navaids, current ARTCC jurisdiction, and glide-reach divert
/// candidates. Deliberately a plain value type over the three bundled indices, not
/// an actor: every query here is a read-only, synchronous computation over
/// already-loaded in-memory data (no I/O), safe to call directly from `@MainActor`
/// UI code the same way `FlightPlan.routeRelative(at:)` already is.
struct RouteIntelligenceEngine {
    let airportIndex: AirportIndex
    let navFixIndex: NavFixIndex
    let artccIndex: ARTCCBoundaryIndex
    let flightPlan: FlightPlan

    struct OnRouteFix: Identifiable, Sendable {
        var id: String { "\(fix.id)-\(Int(alongTrackFlown))" }
        let fix: NavFixRecord
        let alongTrackFlown: Double // m from origin
        let crossTrackError: Double // m, signed
    }

    struct DivertCandidate: Identifiable, Sendable {
        var id: String { airport.icao }
        let airport: AirportRecord
        let distance: Double // m
        let bearing: Double // deg true
        /// distance ÷ height above the airport's own field elevation -- the glide
        /// ratio an unpowered descent would actually need to reach it. Smaller means
        /// easier to reach; compared against `assumedGlideRatio` for `reachable`.
        let requiredGlideRatio: Double
        let reachable: Bool
    }

    /// Every published fix/navaid within `corridorHalfWidth` metres of the filed
    /// great-circle route, sorted along-track. A linear scan over the whole bundled
    /// dataset (~72k points) -- fine to call once at flight start, not per-update;
    /// the route is static for the whole flight, so the caller should cache this.
    func onRouteFixes(corridorHalfWidth: Double = 92_600) -> [OnRouteFix] {
        navFixIndex.records.compactMap { fix in
            let relative = flightPlan.routeRelative(at: fix.coordinate)
            guard abs(relative.crossTrackError) <= corridorHalfWidth else { return nil }
            guard relative.fractionalProgress >= 0, relative.fractionalProgress <= 1 else { return nil }
            return OnRouteFix(
                fix: fix, alongTrackFlown: relative.alongTrackFlown, crossTrackError: relative.crossTrackError
            )
        }.sorted { $0.alongTrackFlown < $1.alongTrackFlown }
    }

    /// The ARTCC whose boundary contains `position` at the tier implied by
    /// `altitudeMSL`. NASR's `ARB_SEG` publishes `HIGH`/`LOW`/`UNLIMITED` boundaries
    /// per center without an explicit numeric floor/ceiling in this dataset, so this
    /// uses the FAA's own structural convention instead: 18,000 ft MSL is Class A
    /// airspace's floor, the same altitude that separates "high" from "low" ARTCC
    /// sectorization nationally. `UNLIMITED`-tier centers (a few oceanic/FIR
    /// entries) are checked at both altitudes as a fallback.
    func currentARTCC(at position: Coordinate, altitudeMSL: Double?) -> ARTCCBoundary? {
        let tier: ARTCCBoundary.AltitudeTier = (altitudeMSL ?? 0) >= 5_486.4 ? .high : .low
        if let match = artccIndex.boundary(containing: position, tier: tier) {
            return match
        }
        return artccIndex.boundary(containing: position, tier: .unlimited)
    }

    /// Airports within unpowered glide range, nearest first. `assumedGlideRatio` is
    /// a stated estimate (17:1 is representative of a clean commercial jet, not a
    /// type-specific figure this app has any way to know) -- surfaced in the UI as
    /// exactly that, an estimate, never a promise.
    func divertCandidates(
        at position: Coordinate, altitudeMSL: Double, assumedGlideRatio: Double = 17
    ) -> [DivertCandidate] {
        // A generous upper-bound search radius: no reachable field can be farther
        // than altitude × glide ratio even at sea level, and real fields (elevation
        // ≥ 0) only shrink that further -- exact filtering happens per-candidate below.
        let searchRadius = max(altitudeMSL, 0) * assumedGlideRatio
        guard searchRadius > 0 else { return [] }

        return airportIndex.within(radius: searchRadius, of: position).compactMap { result in
            let heightAboveField = altitudeMSL - result.payload.elevationMetres
            guard heightAboveField > 0 else { return nil } // at or below the field -- not a glide target
            let required = result.distance / heightAboveField
            return DivertCandidate(
                airport: result.payload, distance: result.distance, bearing: result.bearing,
                requiredGlideRatio: required, reachable: required <= assumedGlideRatio
            )
        }.sorted { $0.distance < $1.distance }
    }
}
