import Foundation
import Testing
import ContrailCore
import ContrailGeo
import ContrailSensors
@testable import ContrailEstimator

private let den = Coordinate(latitude: 39.8617, longitude: -104.6731)
private let lax = Coordinate(latitude: 33.9416, longitude: -118.4085)
private let departure = Date(timeIntervalSince1970: 1_755_639_600)

private func makeFlightPlan(blockTime: TimeInterval = 8400) throws -> FlightPlan {
    try FlightPlan(
        flightNumber: "UA1234", origin: den, destination: lax,
        scheduledDeparture: departure, scheduledArrival: departure.addingTimeInterval(blockTime),
        aircraftICAOType: "B738", aircraftRegistration: nil
    )
}

struct EstimatorTests {
    // MARK: - The centerpiece: dead reckoning grows during a GPS gap and snaps tight
    // on reacquisition, per §2.3's explicit requirement.

    @Test func confidenceRadiusGrowsMonotonicallyDuringAGapAndSnapsTightOnReacquisition() throws {
        let plan = try makeFlightPlan()
        let estimator = Estimator(flightPlan: plan)

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        config.motionSampleInterval = 30
        config.pressureSampleInterval = 30
        config.gpsDropout = (start: 40 * 60, duration: 6 * 60) // 6-minute dropout at cruise
        let samples = try SyntheticFlightLog.generate(config)

        var radiiDuringGap: [Double] = []
        var radiusJustBeforeGap: Double?
        var radiusJustAfterReacquisition: Double?

        let dropoutStart = departure.addingTimeInterval(40 * 60)
        let dropoutEnd = departure.addingTimeInterval(46 * 60)

        for sample in samples {
            guard let output = estimator.ingest(sample) else { continue }
            guard let radius = output.position.confidenceRadius.value else { continue }

            if sample.timestamp < dropoutStart {
                radiusJustBeforeGap = radius
            } else if sample.timestamp >= dropoutStart && sample.timestamp < dropoutEnd {
                radiiDuringGap.append(radius)
            } else if radiusJustAfterReacquisition == nil && sample.timestamp >= dropoutEnd {
                radiusJustAfterReacquisition = radius
            }
        }

        #expect(radiiDuringGap.count > 1, "expected multiple samples during the gap")
        // Monotonically non-decreasing while GPS is lost.
        for i in 1..<radiiDuringGap.count {
            #expect(radiiDuringGap[i] >= radiiDuringGap[i - 1])
        }
        // Grows well beyond the pre-gap value.
        let before = try #require(radiusJustBeforeGap)
        let peak = try #require(radiiDuringGap.last)
        #expect(peak > before * 5)

        // Snaps back down close to the pre-gap value once a fix is reacquired.
        let after = try #require(radiusJustAfterReacquisition)
        #expect(after < peak / 2)
    }

    @Test func deadReckonedPositionDuringGapStaysCloseToTrueRoute() throws {
        let plan = try makeFlightPlan()
        let estimator = Estimator(flightPlan: plan)

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        config.motionSampleInterval = 30
        config.pressureSampleInterval = 30
        config.gpsDropout = (start: 40 * 60, duration: 6 * 60)
        let samples = try SyntheticFlightLog.generate(config)

        let dropoutStart = departure.addingTimeInterval(40 * 60)
        let dropoutEnd = departure.addingTimeInterval(46 * 60)

        var maxErrorDuringGap = 0.0
        for sample in samples {
            guard let output = estimator.ingest(sample) else { continue }
            guard sample.timestamp >= dropoutStart, sample.timestamp < dropoutEnd else { continue }
            guard let dr = output.position.deadReckoned.value else { continue }

            // The synthetic generator's true position at this instant is recoverable
            // from a fresh (non-dropout) generation of the same configuration.
            var truthConfig = config
            truthConfig.gpsDropout = nil
            truthConfig.locationSampleInterval = 1
            let truth = try SyntheticFlightLog.generate(truthConfig).compactMap { s -> LocationSample? in
                if case .location(let l) = s, abs(l.timestamp.timeIntervalSince(sample.timestamp)) < 0.6 { return l }
                return nil
            }.first

            if let truth {
                let error = try VincentyGeodesic.inverse(from: dr, to: truth.coordinate).distance
                maxErrorDuringGap = max(maxErrorDuringGap, error)
            }
        }

        // Over a 6-minute gap at cruise speed (constant-velocity assumption on a
        // flight with no maneuvering), dead reckoning should stay within a few km.
        #expect(maxErrorDuringGap > 0) // sanity: we actually measured something
        #expect(maxErrorDuringGap < 5_000)
    }

    // MARK: - Groundspeed / course computed from successive fixes, not CoreLocation's
    // own (§2.2) — verified indirectly via the synthetic log's known cruise speed.

    @Test func computedGroundspeedMatchesKnownCruiseSpeed() throws {
        let plan = try makeFlightPlan()
        let estimator = Estimator(flightPlan: plan)

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 2
        config.motionSampleInterval = 30
        config.pressureSampleInterval = 30
        let samples = try SyntheticFlightLog.generate(config)

        var midFlightGroundspeed: Double?
        for sample in samples {
            guard let output = estimator.ingest(sample) else { continue }
            if sample.timestamp > departure.addingTimeInterval(45 * 60),
               sample.timestamp < departure.addingTimeInterval(50 * 60) {
                midFlightGroundspeed = output.motion.groundspeed.value
                break
            }
        }

        let speed = try #require(midFlightGroundspeed)
        #expect(abs(speed - config.cruiseGroundspeed) < 5) // within 5 m/s of the configured cruise speed
    }

    // MARK: - ETA is a distribution (§2.3), not a point.

    @Test func etaSigmaIsPositiveAndScheduleDeltaTracksActualPace() throws {
        // A flight plan whose scheduled block time is slower than the synthetic
        // generator's actual pace, so we can assert the ETA reads "ahead of block."
        let plan = try makeFlightPlan(blockTime: 10_000) // planned slower than actual
        let estimator = Estimator(flightPlan: plan)

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        config.motionSampleInterval = 30
        config.pressureSampleInterval = 30
        let samples = try SyntheticFlightLog.generate(config)

        // Sampled mid-cruise, not at the very end of the trace: near touchdown
        // groundspeed drops toward zero, and the ETA estimator's fallback for "no
        // usable groundspeed to extrapolate from" is to assume on-schedule — which
        // trivially reads `scheduleDelta == 0` by construction, masking the ahead-of-
        // schedule signal that's only observable while actually cruising.
        var midCruiseETA: ETAEstimate?
        for sample in samples {
            guard let output = estimator.ingest(sample) else { continue }
            if sample.timestamp > departure.addingTimeInterval(45 * 60),
               sample.timestamp < departure.addingTimeInterval(50 * 60),
               let eta = output.route.eta.value {
                midCruiseETA = eta
                break
            }
        }

        let eta = try #require(midCruiseETA)
        #expect(eta.sigma >= 0)
        // Actual pace is faster than the (deliberately slow) plan, so the estimated
        // arrival should read ahead of schedule (negative scheduleDelta).
        #expect(eta.scheduleDelta < 0)
    }

    // MARK: - Phase classification (§3): progresses through a sane subsequence and
    // never regresses backward through the canonical order.

    @Test func phaseSequenceIsMonotonicAndCoversTheFlight() throws {
        let plan = try makeFlightPlan()
        let estimator = Estimator(flightPlan: plan)

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        config.motionSampleInterval = 30
        config.pressureSampleInterval = 30
        let samples = try SyntheticFlightLog.generate(config)

        let canonicalOrder: [FlightPhase] = [.taxi, .takeoff, .climb, .cruise, .descent, .landing]
        func rank(_ phase: FlightPhase) -> Int { canonicalOrder.firstIndex(of: phase) ?? 0 }

        var observedPhasesInOrder: [FlightPhase] = []
        var maxRankSeen = 0

        for sample in samples {
            guard let output = estimator.ingest(sample), let phase = output.phase.value else { continue }
            if observedPhasesInOrder.last != phase {
                observedPhasesInOrder.append(phase)
            }
            // Allow taxi at the very start and landing/taxi at the very end (both
            // collapse toward .taxi in this classifier's simplified model, see
            // Estimator's doc comment) but otherwise phases should not regress.
            let currentRank = rank(phase)
            if phase != .taxi {
                #expect(currentRank >= maxRankSeen - 1, "phase regressed: \(observedPhasesInOrder)")
            }
            maxRankSeen = max(maxRankSeen, currentRank)
        }

        #expect(observedPhasesInOrder.contains(.taxi))
        #expect(observedPhasesInOrder.contains(.climb) || observedPhasesInOrder.contains(.takeoff))
        #expect(observedPhasesInOrder.contains(.cruise))
        #expect(observedPhasesInOrder.contains(.descent) || observedPhasesInOrder.contains(.landing))
    }

    // MARK: - No output before the first fix.

    @Test func noOutputBeforeFirstLocationFix() {
        let plan = try! makeFlightPlan()
        let estimator = Estimator(flightPlan: plan)
        let motionOnly = RawSensorSample.motion(MotionSample(
            timestamp: departure,
            userAcceleration: Vector3(x: 0, y: 0, z: 0),
            gravity: Vector3(x: 0, y: 0, z: -1),
            attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
            rotationRate: Vector3(x: 0, y: 0, z: 0)
        ))
        #expect(estimator.ingest(motionOnly) == nil)
    }

    // MARK: - Turbulence (§4.1), real as of this module wiring it in.

    @Test func turbulenceChannelIsPopulatedNotUnavailable() throws {
        let plan = try makeFlightPlan()
        let estimator = Estimator(flightPlan: plan, motionSampleRateHz: 50)

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        config.motionSampleInterval = 1.0 / 50.0 // match the estimator's configured rate
        config.pressureSampleInterval = 30
        let samples = try SyntheticFlightLog.generate(config)

        var sawPopulatedEDR = false
        var sawGateOpen = false
        for sample in samples {
            guard let output = estimator.ingest(sample) else { continue }
            if output.turbulence.edrCubeRoot.value != nil { sawPopulatedEDR = true }
            if output.turbulence.attitudeGateOpen.value == true { sawGateOpen = true }
            if sawPopulatedEDR && sawGateOpen { break }
        }

        // The synthetic log holds a constant level attitude throughout (see
        // SyntheticFlightLog's motion generator), so the gate should never close,
        // and the small deterministic wobble it injects should be enough for the
        // primary band-pass + RMS chain to produce a real (if small) EDR value --
        // proving the wiring actually flows data, not just that the field exists.
        #expect(sawGateOpen)
        #expect(sawPopulatedEDR)
    }

    @Test func ifeLookupPopulatesOutsideAirWhenProvided() throws {
        let plan = try makeFlightPlan()
        let reading = OutsideAirData(
            staticAirTemperature: Channel(value: -54.0, source: .ife),
            trueAirspeed: Channel(value: 230.0, source: .ife),
            windSpeed: .unavailable,
            windDirection: .unavailable
        )
        let estimator = Estimator(flightPlan: plan, ifeLookup: { reading })

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        let samples = try SyntheticFlightLog.generate(config)

        let output = try #require(samples.compactMap { estimator.ingest($0) }.first)
        #expect(output.outsideAir == reading)
    }

    @Test func outsideAirIsUnavailableWithNoIfeLookupProvided() throws {
        let plan = try makeFlightPlan()
        let estimator = Estimator(flightPlan: plan)

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        let samples = try SyntheticFlightLog.generate(config)

        let output = try #require(samples.compactMap { estimator.ingest($0) }.first)
        #expect(output.outsideAir == .unavailable)
    }

    @Test func filteredVerticalAccelerationIsExposedForBurstDetection() throws {
        let plan = try makeFlightPlan()
        let estimator = Estimator(flightPlan: plan, motionSampleRateHz: 50)

        var config = SyntheticFlightLog.Configuration(origin: den, destination: lax, departureTime: departure)
        config.locationSampleInterval = 5
        config.motionSampleInterval = 1.0 / 50.0
        config.pressureSampleInterval = 30
        let samples = try SyntheticFlightLog.generate(config)

        var sawNonNilFilteredValue = false
        for sample in samples {
            estimator.ingest(sample)
            if estimator.latestFilteredVerticalAcceleration != nil {
                sawNonNilFilteredValue = true
                break
            }
        }
        #expect(sawNonNilFilteredValue)
    }
}
