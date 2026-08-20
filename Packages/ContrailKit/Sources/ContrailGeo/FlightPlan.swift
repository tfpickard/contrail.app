import Foundation
import ContrailCore

/// §2.1: the immutable description of the flight, resolved before departure — origin,
/// destination, schedule, aircraft type, and the great-circle path between the two
/// airports, with the ability to compute along-track distance, cross-track error, and
/// fractional progress for any given position.
///
/// Lives in `ContrailGeo` rather than `ContrailCore` because its route-relative
/// methods need `VincentyGeodesic`/`GreatCircleTrack`; `ContrailCore` stays
/// dependency-free.
public struct FlightPlan: Sendable, Equatable {
    public let flightNumber: String
    public let origin: Coordinate
    public let destination: Coordinate
    public let scheduledDeparture: Date
    public let scheduledArrival: Date
    /// ICAO aircraft type designator (e.g. `"B738"`), when known.
    public let aircraftICAOType: String?
    public let aircraftRegistration: String?

    /// Total great-circle distance, origin to destination, metres. Computed once via
    /// Vincenty at init — the one-time, highest-precision figure this type exposes;
    /// per-sample route-relative geometry (below) stays spherical, per
    /// `GreatCircleTrack`'s documented rationale.
    public let totalDistance: Double

    public var scheduledBlockTime: TimeInterval {
        scheduledArrival.timeIntervalSince(scheduledDeparture)
    }

    public init(
        flightNumber: String,
        origin: Coordinate,
        destination: Coordinate,
        scheduledDeparture: Date,
        scheduledArrival: Date,
        aircraftICAOType: String?,
        aircraftRegistration: String?
    ) throws {
        self.flightNumber = flightNumber
        self.origin = origin
        self.destination = destination
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.aircraftICAOType = aircraftICAOType
        self.aircraftRegistration = aircraftRegistration
        self.totalDistance = try VincentyGeodesic.inverse(from: origin, to: destination).distance
    }

    /// This position's geometry relative to the filed great-circle route: signed
    /// cross-track error, along-track distance flown and remaining, and fractional
    /// progress. Progress is not clamped to `[0, 1]` — a position beyond the
    /// destination (overflight) or behind the origin yields a value outside that
    /// range, which is itself informative.
    public func routeRelative(at position: Coordinate) -> (
        crossTrackError: Double,
        alongTrackFlown: Double,
        alongTrackRemaining: Double,
        fractionalProgress: Double
    ) {
        let geometry = GreatCircleTrack.relativeGeometry(of: position, start: origin, end: destination)
        let flown = geometry.alongTrackFromStart

        // `remaining` is measured symmetrically — along-track distance from `position`
        // to `destination`, computed by the same spherical construction with the
        // route reversed — rather than as `totalDistance (Vincenty/ellipsoidal) -
        // flown (spherical)`. The subtraction approach mixes two distance models that
        // don't exactly agree, which shows up worst exactly where it matters most:
        // a non-zero "remaining" at touchdown. This construction is self-consistent
        // by definition — it reads exactly zero at the destination and exactly the
        // spherical route length at the origin — at the cost of `flown + remaining`
        // not being bit-identical to `totalDistance` (a sub-0.2% spherical/
        // ellipsoidal difference, immaterial next to GPS position uncertainty).
        let reversed = GreatCircleTrack.relativeGeometry(of: position, start: destination, end: origin)
        let remaining = reversed.alongTrackFromStart

        let progress = totalDistance > 0 ? flown / totalDistance : 0
        return (geometry.crossTrackError, flown, remaining, progress)
    }
}
