import Foundation
import ContrailCore
import ContrailGeo
import ContrailSensors
import ContrailTurbulence

/// §2.3: consumes the raw sensor stream and produces the single fused
/// `EstimatorOutput` — the contract everything downstream depends on.
///
/// Not `Sendable`, deliberately. Per the plan's concurrency design, exactly one
/// writer feeds this class (the app's dedicated sensor-delivery queue in live use,
/// or a sequential loop in tests/replay) — the point of that design is to avoid a
/// per-sample actor hop at 50-100 Hz, and `Estimator` mirrors that by not offering
/// any concurrency safety it doesn't need.
public final class Estimator {
    private let flightPlan: FlightPlan
    private let nearestPlace: @Sendable (Coordinate) -> BearingToPlace?
    private let forecastLookup: @Sendable (_ alongTrackFlown: Double, _ altitudeMetres: Double, _ time: Date) -> Double?
    private let ifeLookup: @Sendable () -> OutsideAirData?

    // MARK: - Raw channel state

    private var previousLocation: LocationSample?
    private var previousComputedCourse: Double?
    private var previousComputedGroundspeed: Double?

    private var latestMotion: MotionSample?
    private var latestPressure: PressureSample?
    private var previousPressure: PressureSample?

    // Derived-from-fixes motion, held between location samples so a motion/pressure
    // sample in between still reports the last known values rather than nil.
    private var computedGroundspeed: Double?
    private var computedCourse: Double?
    private var trackAngleRate: Double?
    private var verticalSpeed: Double?
    private var longitudinalAcceleration: Double?
    private var pressurizationRate: Double?

    // MARK: - Dead reckoning state (§2.3)

    /// Along-track distance (from `flightPlan.origin`) at the last good GPS fix —
    /// the anchor dead reckoning propagates forward from during a gap.
    private var lastGoodFixTime: Date?
    private var lastGoodFixAlongTrack: Double?

    private var latestPhase: FlightPhase?

    // MARK: - Turbulence (§4.1)

    private let turbulenceEstimator: TurbulenceEstimator
    private var latestTurbulenceSample: TurbulenceSample?

    public private(set) var latestOutput: EstimatorOutput?

    /// - Parameters:
    ///   - flightPlan: the resolved route dead reckoning propagates along and route-
    ///     relative geometry is measured against.
    ///   - nearestPlace: injected rather than depending on `ContrailData` directly —
    ///     `Estimator` doesn't need to know how a place index is built or bundled,
    ///     only how to query one. Defaults to always-unavailable, matching `Channel`'s
    ///     "no producer in this build" convention for any caller that hasn't wired a
    ///     dataset in yet.
    ///   - motionSampleRateHz: the device-motion delivery rate — §3's own stated
    ///     50-100 Hz range, defaulting to the low end. `TurbulenceEstimator`'s
    ///     band-pass filters are designed against this rate; passing the wrong value
    ///     silently shifts every cutoff frequency.
    ///   - forecastLookup: §4.2/§4.3's GTG comparison -- injected the same way as
    ///     `nearestPlace`, so `Estimator` stays ignorant of how (or whether) a route
    ///     forecast was fetched. Defaults to always-unavailable.
    ///   - ifeLookup: Phase 3b's IFE moving-map probe -- unlike `forecastLookup`,
    ///     takes no position/time parameters, because IFE data is a live ambient
    ///     reading, not a route-indexed grid to interpolate. The closure returns a
    ///     fully-formed `OutsideAirData` (or `nil`) so the caller -- which knows
    ///     which fields a given endpoint actually reported -- decides per-field
    ///     `.ife` vs `.unavailable`, not `Estimator`. Defaults to always-unavailable.
    public init(
        flightPlan: FlightPlan,
        nearestPlace: @escaping @Sendable (Coordinate) -> BearingToPlace? = { _ in nil },
        motionSampleRateHz: Double = 50.0,
        forecastLookup: @escaping @Sendable (Double, Double, Date) -> Double? = { _, _, _ in nil },
        ifeLookup: @escaping @Sendable () -> OutsideAirData? = { nil }
    ) {
        self.flightPlan = flightPlan
        self.nearestPlace = nearestPlace
        self.forecastLookup = forecastLookup
        self.ifeLookup = ifeLookup
        self.turbulenceEstimator = TurbulenceEstimator(sampleRateHz: motionSampleRateHz)
    }

    /// Feeds one raw sample and returns the freshly recomputed output. Returns `nil`
    /// until at least one GPS fix has been ingested — with no position anchor at all,
    /// there is nothing meaningful to report (no dead-reckoning basis, no
    /// route-relative geometry).
    @discardableResult
    public func ingest(_ sample: RawSensorSample) -> EstimatorOutput? {
        switch sample {
        case .location(let location):
            updateLocation(location)
        case .motion(let motion):
            latestMotion = motion
            latestTurbulenceSample = turbulenceEstimator.ingest(motion)
        case .pressure(let pressure):
            updatePressure(pressure)
        }

        guard previousLocation != nil else { return nil }
        let output = recomputeOutput(at: sample.timestamp)
        latestOutput = output
        return output
    }

    /// The instantaneous (not RMS-smoothed) filtered vertical acceleration, `nil`
    /// while the attitude gate is closed. Not part of `EstimatorOutput`'s schema —
    /// this is raw DSP detail for `AdaptiveLoggingController`'s burst detection
    /// (§3), which needs a fast-reacting signal `EstimatorOutput.turbulence`'s
    /// RMS-smoothed `edrCubeRoot` is deliberately too slow to serve.
    public var latestFilteredVerticalAcceleration: Double? {
        latestTurbulenceSample?.filteredVerticalAcceleration
    }

    // MARK: - Location updates

    private func updateLocation(_ location: LocationSample) {
        defer { previousLocation = location }

        if let previous = previousLocation, location.timestamp > previous.timestamp {
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            if let inverse = try? VincentyGeodesic.inverse(from: previous.coordinate, to: location.coordinate) {
                let groundspeed = inverse.distance / dt
                let course = inverse.initialBearing

                if let previousCourse = previousComputedCourse {
                    trackAngleRate = Estimator.signedAngleDifferenceDegrees(course, previousCourse) / dt
                }
                if let previousSpeed = previousComputedGroundspeed {
                    longitudinalAcceleration = (groundspeed - previousSpeed) / dt
                }
                verticalSpeed = (location.altitude - previous.altitude) / dt

                computedGroundspeed = groundspeed
                computedCourse = course
                previousComputedGroundspeed = groundspeed
                previousComputedCourse = course
            }
        }

        // Re-sync dead reckoning to this good fix — this is the "snaps tight on
        // reacquisition" behavior §2.3 requires of the confidence radius, and it
        // falls out naturally here: every fresh fix resets the dead-reckoning anchor.
        let routeGeometry = flightPlan.routeRelative(at: location.coordinate)
        lastGoodFixTime = location.timestamp
        lastGoodFixAlongTrack = routeGeometry.alongTrackFlown
    }

    private func updatePressure(_ pressure: PressureSample) {
        if let previous = latestPressure, pressure.timestamp > previous.timestamp {
            let dt = pressure.timestamp.timeIntervalSince(previous.timestamp)
            let previousAltitude = ISAAtmosphere.altitude(pressureKPa: previous.kilopascals)
            let currentAltitude = ISAAtmosphere.altitude(pressureKPa: pressure.kilopascals)
            pressurizationRate = (currentAltitude - previousAltitude) / dt
        }
        previousPressure = latestPressure
        latestPressure = pressure
    }

    // MARK: - Output assembly

    private func recomputeOutput(at now: Date) -> EstimatorOutput {
        let position = assemblePosition(at: now)
        let motion = assembleMotion()
        let cabin = assembleCabin()
        let route = assembleRoute(fusedPosition: position.fused.value, at: now)
        let phase = classifyAndTrackPhase(
            groundspeed: computedGroundspeed,
            verticalSpeed: verticalSpeed,
            pressurizationRate: pressurizationRate
        )

        return EstimatorOutput(
            t: now,
            uptime: now.timeIntervalSince1970,
            position: position,
            motion: motion,
            cabin: cabin,
            turbulence: assembleTurbulence(
                alongTrackFlown: route.alongTrackFlown.value, altitudeMetres: position.altitudeGPS.value, at: now
            ),
            route: route,
            phase: phase,
            outsideAir: ifeLookup() ?? .unavailable
        )
    }

    /// §4.1's measured turbulence, real as of 1.2. §4.3's forecast comparison, real
    /// as of 1.6 -- `forecastLookup` answers `nil` (reported as `.unavailable`, not
    /// a stub value) whenever no route forecast was fetched pre-flight, or the
    /// current position/altitude/time falls outside what was fetched.
    private func assembleTurbulence(alongTrackFlown: Double?, altitudeMetres: Double?, at time: Date) -> TurbulenceEstimate {
        guard let sample = latestTurbulenceSample else { return .unavailable }

        let forecast: Channel<Double>
        if let alongTrackFlown, let altitudeMetres,
           let value = forecastLookup(alongTrackFlown, altitudeMetres, time) {
            forecast = Channel(value: value, source: .forecast)
        } else {
            forecast = .unavailable
        }

        return TurbulenceEstimate(
            edrCubeRoot: sample.edrCubeRoot.map { Channel(value: $0, source: .derived) } ?? .unavailable,
            forecastEdrCubeRoot: forecast,
            attitudeGateOpen: Channel(value: sample.attitudeGateOpen, source: .derived)
        )
    }

    /// Both the GNSS/dead-reckoning fusion and the confidence radius — §2.3's
    /// centerpiece. A fix younger than `freshFixWindow` is trusted directly; anything
    /// older falls back to the position dead-reckoned from the last good fix, and the
    /// confidence radius grows with how long that's been.
    private func assemblePosition(at now: Date) -> PositionEstimate {
        guard let fixTime = lastGoodFixTime, let fixAlongTrack = lastGoodFixAlongTrack,
              let location = previousLocation else {
            // Unreachable in practice — `ingest` already gates on `previousLocation`
            // being non-nil before calling this — but keeps this function total.
            return PositionEstimate(
                fused: .unavailable, confidenceRadius: .unavailable,
                gnss: .unavailable, deadReckoned: .unavailable,
                horizontalAccuracy: .unavailable, verticalAccuracy: .unavailable,
                timeSinceValidFix: .unavailable, altitudeGPS: .unavailable
            )
        }

        let timeSinceFix = now.timeIntervalSince(fixTime)
        let freshFixWindow = 2.0 // seconds

        let deadReckonedAlongTrack = fixAlongTrack + (computedGroundspeed ?? 0) * timeSinceFix
        let deadReckonedCoordinate = try? flightPlan.position(atAlongTrackDistance: deadReckonedAlongTrack)

        let baseAccuracy = location.horizontalAccuracy
        // A dead-reckoning error-growth heuristic: uncertainty grows with distance
        // covered since the last fix, not just elapsed time, so a stationary aircraft
        // (unusual, but possible on a long ground hold) doesn't accrue phantom error.
        let driftFraction = 0.05
        let distanceSinceFix = abs(computedGroundspeed ?? 0) * max(0, timeSinceFix)
        let confidenceRadius = baseAccuracy + driftFraction * distanceSinceFix

        let isFresh = timeSinceFix < freshFixWindow
        let fusedCoordinate = isFresh ? location.coordinate : (deadReckonedCoordinate ?? location.coordinate)
        let fusedSource: ChannelSource = isFresh ? .fused : .deadReckoned

        return PositionEstimate(
            fused: Channel(value: fusedCoordinate, source: fusedSource, age: timeSinceFix),
            confidenceRadius: Channel(value: confidenceRadius, source: .derived, age: timeSinceFix),
            gnss: Channel(value: location.coordinate, source: .gnss, age: timeSinceFix),
            deadReckoned: deadReckonedCoordinate.map { Channel(value: $0, source: .deadReckoned, age: timeSinceFix) }
                ?? .unavailable,
            horizontalAccuracy: Channel(value: location.horizontalAccuracy, source: .gnss, age: timeSinceFix),
            verticalAccuracy: Channel(value: location.verticalAccuracy, source: .gnss, age: timeSinceFix),
            timeSinceValidFix: Channel(value: timeSinceFix, source: .derived, age: 0),
            altitudeGPS: Channel(value: location.altitude, source: .gnss, age: timeSinceFix)
        )
    }

    private func assembleMotion() -> MotionEstimate {
        MotionEstimate(
            groundspeed: computedGroundspeed.map { Channel(value: $0, source: .derived) } ?? .unavailable,
            trueCourse: computedCourse.map { Channel(value: $0, source: .derived) } ?? .unavailable,
            trackAngleRate: trackAngleRate.map { Channel(value: $0, source: .derived) } ?? .unavailable,
            verticalSpeed: verticalSpeed.map { Channel(value: $0, source: .derived) } ?? .unavailable,
            longitudinalAcceleration: longitudinalAcceleration.map { Channel(value: $0, source: .derived) } ?? .unavailable,
            // §2.2: CoreLocation's own speed/course, carried separately, never fused
            // into the channels above.
            clSpeed: previousLocation?.speed.map { Channel(value: $0, source: .gnss) } ?? .unavailable,
            clCourse: previousLocation?.course.map { Channel(value: $0, source: .gnss) } ?? .unavailable
        )
    }

    private func assembleCabin() -> CabinEnvironment {
        guard let pressure = latestPressure else {
            return CabinEnvironment(pressure: .unavailable, pressureAltitude: .unavailable, pressurizationRate: .unavailable)
        }
        let pressureAltitude = ISAAtmosphere.altitude(pressureKPa: pressure.kilopascals)
        return CabinEnvironment(
            pressure: Channel(value: pressure.kilopascals, source: .barometer),
            pressureAltitude: Channel(value: pressureAltitude, source: .derived),
            pressurizationRate: pressurizationRate.map { Channel(value: $0, source: .derived) } ?? .unavailable
        )
    }

    private func assembleRoute(fusedPosition: Coordinate?, at now: Date) -> RouteRelative {
        guard let position = fusedPosition else {
            return RouteRelative(
                alongTrackFlown: .unavailable, alongTrackRemaining: .unavailable,
                crossTrackError: .unavailable, fractionalProgress: .unavailable,
                nearestCity: .unavailable, eta: .unavailable
            )
        }

        let geometry = flightPlan.routeRelative(at: position)
        let place = nearestPlace(position)

        return RouteRelative(
            alongTrackFlown: Channel(value: geometry.alongTrackFlown, source: .derived),
            alongTrackRemaining: Channel(value: geometry.alongTrackRemaining, source: .derived),
            crossTrackError: Channel(value: geometry.crossTrackError, source: .derived),
            fractionalProgress: Channel(value: geometry.fractionalProgress, source: .derived),
            nearestCity: place.map { Channel(value: $0, source: .derived) } ?? .unavailable,
            eta: Channel(value: estimateArrival(remainingDistance: geometry.alongTrackRemaining, at: now), source: .derived)
        )
    }

    /// §2.3: "ETA must be a distribution, not a point... fold in the current
    /// groundspeed residual against planned." `sigma` grows both with how far out the
    /// ETA is (baseline proportional uncertainty) and with how much current
    /// groundspeed has diverged from the plan's implied average — a fast/slow
    /// aircraft is a less certain ETA than one tracking the filed schedule.
    private func estimateArrival(remainingDistance: Double, at now: Date) -> ETAEstimate {
        let plannedGroundspeed = flightPlan.scheduledBlockTime > 0
            ? flightPlan.totalDistance / flightPlan.scheduledBlockTime : 0
        let currentGroundspeed = computedGroundspeed ?? plannedGroundspeed

        let remainingTime: TimeInterval
        if currentGroundspeed > 1 {
            remainingTime = remainingDistance / currentGroundspeed
        } else {
            remainingTime = max(0, flightPlan.scheduledArrival.timeIntervalSince(now))
        }

        let arrival = now.addingTimeInterval(max(0, remainingTime))
        let speedResidualFraction = plannedGroundspeed > 0
            ? min(1, abs(currentGroundspeed - plannedGroundspeed) / plannedGroundspeed) : 0
        let sigma = max(0, remainingTime) * (0.05 + 0.5 * speedResidualFraction)
        let scheduleDelta = arrival.timeIntervalSince(flightPlan.scheduledArrival)

        return ETAEstimate(arrival: arrival, sigma: sigma, scheduleDelta: scheduleDelta)
    }

    // MARK: - Phase classification (§3)

    /// A threshold classifier over the three signals §3 names — groundspeed, vertical
    /// rate, and pressurization rate. Deliberately does not use absolute altitude:
    /// without airport elevation (a `ContrailData` concern, not yet wired into this
    /// module — see `Estimator.init`'s `nearestPlace` injection for the analogous
    /// pattern), "near the ground" has no fixed absolute threshold that works across
    /// airports at wildly different elevations, whereas groundspeed and vertical rate
    /// are self-calibrating.
    private func classifyAndTrackPhase(
        groundspeed: Double?,
        verticalSpeed: Double?,
        pressurizationRate: Double?
    ) -> Channel<FlightPhase> {
        guard let groundspeed else { return latestPhase.map { Channel(value: $0, source: .derived) } ?? .unavailable }

        let taxiSpeed = 15.0             // m/s, ~30 kt
        let climbVerticalSpeed = 2.0     // m/s
        let descentVerticalSpeed = -2.0  // m/s
        let significantPressurizationRate = -1.5 // m/s of pressure altitude — descending fast

        let phase: FlightPhase
        if groundspeed < taxiSpeed {
            phase = .taxi
        } else if (verticalSpeed ?? 0) <= descentVerticalSpeed
            || (pressurizationRate ?? 0) <= significantPressurizationRate {
            // Pressurization rate is the strongest *early* descent signal (§3) — it
            // can flag the phase change before vertical speed alone would.
            phase = groundspeed < taxiSpeed * 3 ? .landing : .descent
        } else if (verticalSpeed ?? 0) >= climbVerticalSpeed {
            phase = latestPhase == .taxi ? .takeoff : .climb
        } else {
            phase = .cruise
        }

        latestPhase = phase
        return Channel(value: phase, source: .derived)
    }

    private static func signedAngleDifferenceDegrees(_ a: Double, _ b: Double) -> Double {
        let diff = (a - b).truncatingRemainder(dividingBy: 360)
        if diff > 180 { return diff - 360 }
        if diff < -180 { return diff + 360 }
        return diff
    }
}
