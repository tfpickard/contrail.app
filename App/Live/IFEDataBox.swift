import Foundation
import ContrailCore

/// Bridges the continuously-repolled IFE reading (written every probe interval from
/// a `@MainActor` polling `Task`) to `Estimator`'s `ifeLookup` closure (read at full
/// sensor rate from `FlightEstimationEngine`'s own actor) -- same shape as
/// `ForecastCacheBox`, except written repeatedly over the life of the flight rather
/// than once at the start, since an IFE reading goes stale in seconds, not the whole
/// flight.
final class IFEDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: OutsideAirData?

    func set(_ reading: OutsideAirData?) {
        lock.lock()
        defer { lock.unlock() }
        latest = reading
    }

    func value() -> OutsideAirData? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}
