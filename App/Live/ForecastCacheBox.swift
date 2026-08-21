import Foundation
import ContrailForecast

/// Bridges the pre-flight-fetched `RouteForecastCache` (written once, on
/// `@MainActor`, when the fetch completes) to `Estimator`'s `forecastLookup`
/// closure (read continuously, from `FlightEstimationEngine`'s own actor at full
/// sensor rate) -- the same "construct once, hand off, single owner from then on"
/// shape as `NDJSONLogWriter`, except this one genuinely is read from a different
/// isolation domain than it's written from, so it needs the lock `NDJSONLogWriter`
/// doesn't.
final class ForecastCacheBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: RouteForecastCache?

    func set(_ cache: RouteForecastCache?) {
        lock.lock()
        defer { lock.unlock() }
        self.cache = cache
    }

    func value(alongTrackFlown: Double, altitudeMetres: Double, time: Date) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return cache?.value(alongTrackFlown: alongTrackFlown, altitudeMetres: altitudeMetres, time: time)
    }
}
