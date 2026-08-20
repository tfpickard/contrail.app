/// §2.3 position/motion contract. Two independent position estimates are carried
/// side by side and fused: `gnss` (high confidence, intermittent — GPS drops
/// constantly in a cabin) and `deadReckoned` (always available, degrading with time
/// since the last fix). `fused` is what the UI displays; `confidenceRadius` is the
/// honesty mechanism the README insists on — no fake blue dot.
public struct PositionEstimate: Sendable, Codable, Equatable {
    public let fused: Channel<Coordinate>
    public let confidenceRadius: Channel<Double>       // metres; grows during GPS loss, snaps tight on reacquisition
    public let gnss: Channel<Coordinate>
    public let deadReckoned: Channel<Coordinate>

    // §2.2: the only fix-quality signals iOS actually exposes. No satellite count,
    // no per-constellation breakdown, no DOP — see the fix-quality panel (§8).
    public let horizontalAccuracy: Channel<Double>     // metres
    public let verticalAccuracy: Channel<Double>       // metres
    public let timeSinceValidFix: Channel<Double>      // seconds

    public let altitudeGPS: Channel<Double>            // metres, WGS-84 ellipsoidal (not MSL)

    public init(
        fused: Channel<Coordinate>,
        confidenceRadius: Channel<Double>,
        gnss: Channel<Coordinate>,
        deadReckoned: Channel<Coordinate>,
        horizontalAccuracy: Channel<Double>,
        verticalAccuracy: Channel<Double>,
        timeSinceValidFix: Channel<Double>,
        altitudeGPS: Channel<Double>
    ) {
        self.fused = fused
        self.confidenceRadius = confidenceRadius
        self.gnss = gnss
        self.deadReckoned = deadReckoned
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.timeSinceValidFix = timeSinceValidFix
        self.altitudeGPS = altitudeGPS
    }
}

/// §2.2: CoreLocation's `speed` and `course` are filtered for terrestrial motion and
/// are unreliable at 500 kt. `clSpeed`/`clCourse` carry those raw values, labelled and
/// displayed separately for comparison — never fused into `groundspeed`/`trueCourse`,
/// which are always computed from successive fixes via geodesic inverse.
public struct MotionEstimate: Sendable, Codable, Equatable {
    public let groundspeed: Channel<Double>            // m/s — COMPUTED, geodesic inverse
    public let trueCourse: Channel<Double>             // degrees true — COMPUTED
    public let trackAngleRate: Channel<Double>         // degrees/s, rate of turn
    public let verticalSpeed: Channel<Double>          // m/s, from altitude deltas
    public let longitudinalAcceleration: Channel<Double> // m/s²

    public let clSpeed: Channel<Double>                // m/s, CoreLocation's own value
    public let clCourse: Channel<Double>               // degrees true, CoreLocation's own value

    public init(
        groundspeed: Channel<Double>,
        trueCourse: Channel<Double>,
        trackAngleRate: Channel<Double>,
        verticalSpeed: Channel<Double>,
        longitudinalAcceleration: Channel<Double>,
        clSpeed: Channel<Double>,
        clCourse: Channel<Double>
    ) {
        self.groundspeed = groundspeed
        self.trueCourse = trueCourse
        self.trackAngleRate = trackAngleRate
        self.verticalSpeed = verticalSpeed
        self.longitudinalAcceleration = longitudinalAcceleration
        self.clSpeed = clSpeed
        self.clCourse = clCourse
    }
}
