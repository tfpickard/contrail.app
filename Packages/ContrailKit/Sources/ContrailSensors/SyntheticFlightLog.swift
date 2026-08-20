import Foundation
import ContrailCore
import ContrailGeo

/// §2.2's required deliverable: "Ship a bundled sample log so the app is exercisable
/// on a desk." Rather than a static hand-authored fixture, this is a deterministic
/// *generator* — parameterized by route, timing, and dropout window — so the same
/// generator drives package tests (exact, reproducible), the estimator's
/// dead-reckoning verification, and (once the App target exists) a bundled on-device
/// demo log written once at build time.
///
/// The generated ground track follows a **constant initial bearing** from origin to
/// destination — a rhumb-line approximation, not the true curving geodesic — which
/// diverges from the real great circle by at most a few km on a flight this length.
/// That is immaterial for a synthetic test fixture and dramatically simpler than
/// stepping along the true geodesic; `ContrailGeo`'s own geodesic math, which this
/// data exists to exercise, is exact regardless of how the fixture was generated.
public enum SyntheticFlightLog {
    public struct Configuration: Sendable {
        public var origin: Coordinate
        public var destination: Coordinate
        public var departureTime: Date

        public var groundElevation: Double = 1600       // metres, both ends (simplification)
        public var cruiseAltitude: Double = 11_500       // metres (~FL377)
        public var cruiseGroundspeed: Double = 240        // m/s (~467 kt)
        public var climbDuration: TimeInterval = 25 * 60
        public var descentDuration: TimeInterval = 22 * 60
        public var taxiDuration: TimeInterval = 8 * 60

        public var locationSampleInterval: TimeInterval = 1.0
        /// Real hardware runs CMDeviceMotion at 50-100 Hz (§3); this generator
        /// defaults far lower so a multi-hour synthetic flight stays a manageable
        /// fixture size. Callers exercising rate-sensitive logic (e.g. a future 1.2
        /// turbulence DSP test) should override this per test.
        public var motionSampleInterval: TimeInterval = 0.1
        public var pressureSampleInterval: TimeInterval = 1.0

        /// A deliberate GPS dropout: no `.location` samples in this window, while
        /// `.motion` and `.pressure` continue uninterrupted — the realistic failure
        /// mode dead reckoning (§2.3) exists to cover. `nil` disables the dropout.
        public var gpsDropout: (start: TimeInterval, duration: TimeInterval)? = nil

        public init(origin: Coordinate, destination: Coordinate, departureTime: Date) {
            self.origin = origin
            self.destination = destination
            self.departureTime = departureTime
        }
    }

    /// Generates a full synthetic flight: taxi, climb, cruise, descent, taxi-in,
    /// covering the exact great-circle distance between `origin` and `destination`.
    public static func generate(_ config: Configuration) throws -> [RawSensorSample] {
        let route = try VincentyGeodesic.inverse(from: config.origin, to: config.destination)
        let totalDistance = route.distance
        let bearing = route.initialBearing

        // Trapezoidal ramps: climb accelerates 0 -> cruiseSpeed, descent decelerates
        // cruiseSpeed -> 0, so each covers (average speed * duration).
        let climbDistance = (config.cruiseGroundspeed / 2) * config.climbDuration
        let descentDistance = (config.cruiseGroundspeed / 2) * config.descentDuration
        let cruiseDistance = max(0, totalDistance - climbDistance - descentDistance)
        let cruiseDuration = cruiseDistance / config.cruiseGroundspeed

        let climbEnd = config.taxiDuration + config.climbDuration
        let cruiseEnd = climbEnd + cruiseDuration
        let descentEnd = cruiseEnd + config.descentDuration
        let totalDuration = descentEnd + config.taxiDuration

        // Kinematic profile as pure functions of elapsed time, t in [0, totalDuration].
        func groundspeed(at t: TimeInterval) -> Double {
            switch t {
            case ..<config.taxiDuration:
                return 0
            case ..<climbEnd:
                let frac = (t - config.taxiDuration) / config.climbDuration
                return config.cruiseGroundspeed * frac
            case ..<cruiseEnd:
                return config.cruiseGroundspeed
            case ..<descentEnd:
                let frac = (t - cruiseEnd) / config.descentDuration
                return config.cruiseGroundspeed * (1 - frac)
            default:
                return 0
            }
        }

        func altitude(at t: TimeInterval) -> Double {
            switch t {
            case ..<config.taxiDuration:
                return config.groundElevation
            case ..<climbEnd:
                let frac = (t - config.taxiDuration) / config.climbDuration
                return config.groundElevation + (config.cruiseAltitude - config.groundElevation) * frac
            case ..<cruiseEnd:
                return config.cruiseAltitude
            case ..<descentEnd:
                let frac = (t - cruiseEnd) / config.descentDuration
                return config.cruiseAltitude - (config.cruiseAltitude - config.groundElevation) * frac
            default:
                return config.groundElevation
            }
        }

        // Cabin pressure altitude tracks true altitude below ~2400 m (unpressurized
        // regime) and holds near a constant cabin altitude at cruise — a simplified
        // but directionally correct pressurization schedule.
        func cabinPressureKPa(at t: TimeInterval) -> Double {
            let cabinAltitude = min(altitude(at: t), 2400) // metres, capped cabin altitude
            return isaPressureKPa(altitude: cabinAltitude)
        }

        var samples: [RawSensorSample] = []
        var alongTrackDistance = 0.0
        var previousLocationTime = 0.0

        // Location samples: numerically integrate groundspeed to get along-track
        // distance, then place the point via constant-bearing direct().
        var t = 0.0
        while t <= totalDuration {
            let dt = t - previousLocationTime
            if t > 0 {
                alongTrackDistance += groundspeed(at: t) * dt
            }
            previousLocationTime = t

            let inDropout: Bool = {
                guard let dropout = config.gpsDropout else { return false }
                return t >= dropout.start && t < dropout.start + dropout.duration
            }()

            if !inDropout {
                let position = try VincentyGeodesic.direct(
                    from: config.origin,
                    initialBearing: bearing,
                    distance: min(alongTrackDistance, totalDistance)
                )
                let timestamp = config.departureTime.addingTimeInterval(t)
                let speed = groundspeed(at: t)
                samples.append(.location(LocationSample(
                    timestamp: timestamp,
                    coordinate: position.destination,
                    altitude: altitude(at: t),
                    horizontalAccuracy: speed > 1 ? 8.0 : 4.0,
                    verticalAccuracy: 12.0,
                    speed: speed > 0.5 ? speed : nil,
                    course: speed > 0.5 ? bearing : nil
                )))
            }
            t += config.locationSampleInterval
        }

        // Motion samples: near-level attitude with small deterministic (sinusoidal,
        // not random) variation so the fixture is exactly reproducible.
        t = 0.0
        while t <= totalDuration {
            let wobble = sin(t * 0.7) * 0.02
            samples.append(.motion(MotionSample(
                timestamp: config.departureTime.addingTimeInterval(t),
                userAcceleration: Vector3(x: wobble, y: sin(t * 1.3) * 0.015, z: cos(t * 0.9) * 0.01),
                gravity: Vector3(x: 0, y: 0, z: -1),
                attitude: Quaternion(x: 0, y: 0, z: 0, w: 1),
                rotationRate: Vector3(x: sin(t * 0.4) * 0.005, y: 0, z: cos(t * 0.6) * 0.005)
            )))
            t += config.motionSampleInterval
        }

        // Pressure samples.
        t = 0.0
        while t <= totalDuration {
            samples.append(.pressure(PressureSample(
                timestamp: config.departureTime.addingTimeInterval(t),
                kilopascals: cabinPressureKPa(at: t)
            )))
            t += config.pressureSampleInterval
        }

        return samples.sorted { $0.timestamp < $1.timestamp }
    }

    /// ISA barometric formula, troposphere (below 11 km): P = P0 * (1 - L*h/T0)^(g*M/(R*L)).
    private static func isaPressureKPa(altitude h: Double) -> Double {
        let P0 = 101.325   // kPa, sea-level standard pressure
        let T0 = 288.15    // K, sea-level standard temperature
        let L = 0.0065     // K/m, temperature lapse rate
        let g = 9.80665    // m/s²
        let M = 0.0289644  // kg/mol, molar mass of air
        let R = 8.3144598   // J/(mol·K)
        return P0 * pow(1 - (L * h) / T0, (g * M) / (R * L))
    }
}
