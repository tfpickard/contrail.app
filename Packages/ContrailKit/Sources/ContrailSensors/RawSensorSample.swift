import Foundation
import ContrailCore

/// A plain 3-component vector — deliberately not `simd`, to keep this package's
/// public surface free of any dependency beyond Foundation.
public struct Vector3: Sendable, Codable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// A device attitude quaternion.
public struct Quaternion: Sendable, Codable, Equatable {
    public let x: Double
    public let y: Double
    public let z: Double
    public let w: Double

    public init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }
}

/// §2.2: a raw CoreLocation fix. `speed`/`course` are CoreLocation's own filtered
/// values — carried here only so the app can display them labelled, separately, for
/// comparison; `ContrailEstimator` never fuses them into `MotionEstimate`'s computed
/// `groundspeed`/`trueCourse`. `nil` means CoreLocation reported the value invalid
/// (its own `-1` sentinel), which the live adapter is responsible for translating.
public struct LocationSample: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let coordinate: Coordinate
    public let altitude: Double              // metres, WGS-84 ellipsoidal (GPS altitude)
    public let horizontalAccuracy: Double    // metres
    public let verticalAccuracy: Double      // metres
    public let speed: Double?                // m/s, CoreLocation's own value
    public let course: Double?               // degrees true, CoreLocation's own value

    public init(
        timestamp: Date,
        coordinate: Coordinate,
        altitude: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        speed: Double?,
        course: Double?
    ) {
        self.timestamp = timestamp
        self.coordinate = coordinate
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.course = course
    }
}

/// §2.2: one CMDeviceMotion sample. `userAcceleration` already has gravity
/// subtracted (CoreMotion's own separation); `gravity` is that removed component, a
/// unit vector giving "down" in device space — this is what §4.1's turbulence
/// measurement (1.2) rotates into the world frame.
public struct MotionSample: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let userAcceleration: Vector3     // m/s², gravity removed
    public let gravity: Vector3              // unit vector, device frame
    public let attitude: Quaternion
    public let rotationRate: Vector3         // rad/s

    public init(
        timestamp: Date,
        userAcceleration: Vector3,
        gravity: Vector3,
        attitude: Quaternion,
        rotationRate: Vector3
    ) {
        self.timestamp = timestamp
        self.userAcceleration = userAcceleration
        self.gravity = gravity
        self.attitude = attitude
        self.rotationRate = rotationRate
    }
}

/// §2.2: one CMAltimeter sample. This is **cabin** pressure — CMAltimeter has no
/// access to ambient/outside pressure, ever.
public struct PressureSample: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let kilopascals: Double

    public init(timestamp: Date, kilopascals: Double) {
        self.timestamp = timestamp
        self.kilopascals = kilopascals
    }
}

/// §2.2's unified sensor stream: raw, heterogeneous, timestamped samples arriving at
/// each channel's own native rate — GNSS at ~1 Hz, motion at 50-100 Hz, the
/// altimeter at ~1 Hz. Deliberately *not* one struct combining every channel at a
/// synchronized instant: fusing and resampling onto a common timeline is
/// `ContrailEstimator`'s job, not this layer's.
public enum RawSensorSample: Sendable, Equatable {
    case location(LocationSample)
    case motion(MotionSample)
    case pressure(PressureSample)

    public var timestamp: Date {
        switch self {
        case .location(let s): return s.timestamp
        case .motion(let s): return s.timestamp
        case .pressure(let s): return s.timestamp
        }
    }
}

extension RawSensorSample: Codable {
    private enum Kind: String, Codable {
        case location, motion, pressure
    }
    private enum CodingKeys: String, CodingKey {
        case kind, payload
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .location(let s):
            try container.encode(Kind.location, forKey: .kind)
            try container.encode(s, forKey: .payload)
        case .motion(let s):
            try container.encode(Kind.motion, forKey: .kind)
            try container.encode(s, forKey: .payload)
        case .pressure(let s):
            try container.encode(Kind.pressure, forKey: .kind)
            try container.encode(s, forKey: .payload)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .location:
            self = .location(try container.decode(LocationSample.self, forKey: .payload))
        case .motion:
            self = .motion(try container.decode(MotionSample.self, forKey: .payload))
        case .pressure:
            self = .pressure(try container.decode(PressureSample.self, forKey: .payload))
        }
    }
}
