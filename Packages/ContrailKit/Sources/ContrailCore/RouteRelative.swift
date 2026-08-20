import Foundation

/// §2.3: ETA is a distribution, not a point — folding in the current groundspeed
/// residual against planned. Renders as e.g. "38 min, ±6, running 11 min ahead of
/// block."
public struct ETAEstimate: Sendable, Codable, Equatable {
    public let arrival: Date
    public let sigma: TimeInterval        // seconds, one standard deviation
    public let scheduleDelta: TimeInterval // seconds; negative = ahead of block time

    public init(arrival: Date, sigma: TimeInterval, scheduleDelta: TimeInterval) {
        self.arrival = arrival
        self.sigma = sigma
        self.scheduleDelta = scheduleDelta
    }
}

/// §2.1/§2.3: everything computed relative to the filed great-circle route.
/// `crossTrackError` is signed so left/right of course is distinguishable — with no
/// filed route deviation to compare against, it doubles as a live reroute indicator.
public struct RouteRelative: Sendable, Codable, Equatable {
    public let alongTrackFlown: Channel<Double>         // metres
    public let alongTrackRemaining: Channel<Double>     // metres
    public let crossTrackError: Channel<Double>         // metres, signed (+ = right of course)
    public let fractionalProgress: Channel<Double>      // 0...1
    public let nearestCity: Channel<BearingToPlace>
    public let eta: Channel<ETAEstimate>

    public init(
        alongTrackFlown: Channel<Double>,
        alongTrackRemaining: Channel<Double>,
        crossTrackError: Channel<Double>,
        fractionalProgress: Channel<Double>,
        nearestCity: Channel<BearingToPlace>,
        eta: Channel<ETAEstimate>
    ) {
        self.alongTrackFlown = alongTrackFlown
        self.alongTrackRemaining = alongTrackRemaining
        self.crossTrackError = crossTrackError
        self.fractionalProgress = fractionalProgress
        self.nearestCity = nearestCity
        self.eta = eta
    }
}
