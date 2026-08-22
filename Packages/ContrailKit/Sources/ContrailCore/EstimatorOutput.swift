import Foundation

/// The single fused output of the Estimator (§2.3) — the contract everything
/// downstream depends on. Produced once per sensor update by `ContrailEstimator`,
/// consumed by the UI, the logger, and the statistics engine (1.1) alike.
///
/// Every field that Phase 1.0 doesn't populate — `turbulence` (1.2) — is present in
/// the shape from day one and reports `.unavailable`. See `Channel` for why.
public struct EstimatorOutput: Sendable, Codable, Equatable {
    public let t: Date                 // wall clock, derived from the monotonic base
    public let uptime: TimeInterval    // monotonic seconds; survives clock adjustment

    public let position: PositionEstimate
    public let motion: MotionEstimate
    public let cabin: CabinEnvironment
    public let turbulence: TurbulenceEstimate
    public let route: RouteRelative
    public let phase: Channel<FlightPhase>
    /// Phase 3b -- `.unavailable` on every build until an IFE endpoint is actually
    /// reachable and probed. See `OutsideAirData`'s own doc comment.
    public let outsideAir: OutsideAirData

    public init(
        t: Date,
        uptime: TimeInterval,
        position: PositionEstimate,
        motion: MotionEstimate,
        cabin: CabinEnvironment,
        turbulence: TurbulenceEstimate,
        route: RouteRelative,
        phase: Channel<FlightPhase>,
        outsideAir: OutsideAirData = .unavailable
    ) {
        self.t = t
        self.uptime = uptime
        self.position = position
        self.motion = motion
        self.cabin = cabin
        self.turbulence = turbulence
        self.route = route
        self.phase = phase
        self.outsideAir = outsideAir
    }
}
