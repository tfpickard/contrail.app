import Foundation
import ContrailLog

/// ROADMAP Phase 2 -- Identity: "several people on the same flight -- family,
/// colleagues, friends -- each running the app, producing one combined record."
/// A `GroupFlightRecord` is that combined record: every participant's own package,
/// kept intact and separate (never averaged into a single track or a single
/// turbulence trace) because the point is that they're sitting in *different*
/// seats on the *same* airframe -- "genuinely different turbulence traces" is the
/// interesting part, not something to smooth away.
public struct GroupFlightRecord: Sendable, Equatable {
    public let participants: [FlightExportPackage]

    fileprivate init(participants: [FlightExportPackage]) {
        self.participants = participants
    }
}

public enum GroupFlightError: Error, Equatable {
    /// Fewer than two participants -- a "group" of one is just a flight.
    case tooFewParticipants
    /// Two packages whose `manifest.flight.number`/`date` don't match, so they
    /// can't honestly be claimed as the same flight.
    case mismatchedFlights(FlightExportPackage, FlightExportPackage)
}

/// Whether two exported packages represent the same physical flight. Matched on
/// flight number + local date rather than any generated identifier -- those are
/// exactly the two fields a boarding pass carries, and exactly what two strangers
/// on the same aircraft can independently confirm they share.
public enum GroupFlightMatcher {
    public static func sameFlight(_ a: FlightManifest, _ b: FlightManifest) -> Bool {
        a.flight.number == b.flight.number && a.flight.date == b.flight.date
    }
}

public enum GroupFlightBuilder {
    /// Builds a `GroupFlightRecord` from participant packages, validating that
    /// every package claims the same flight before combining them. Order is
    /// preserved -- the caller typically puts "you" first.
    public static func build(from packages: [FlightExportPackage]) throws -> GroupFlightRecord {
        guard packages.count >= 2 else { throw GroupFlightError.tooFewParticipants }
        let first = packages[0]
        for other in packages.dropFirst() where !GroupFlightMatcher.sameFlight(first.manifest, other.manifest) {
            throw GroupFlightError.mismatchedFlights(first, other)
        }
        return GroupFlightRecord(participants: packages)
    }
}
