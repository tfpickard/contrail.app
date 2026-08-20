import Foundation
import ContrailSensors

/// §4.1: "gate on attitude stability. If the attitude quaternion is changing
/// materially during a window, discard that window entirely. This is the primary
/// discriminator against handling motion, and it is cheap." Handling motion (picking
/// the phone up, adjusting it) presents as a real, deliberate change in device
/// orientation over ~1-2 seconds; genuine turbulence at the tray table does not
/// meaningfully reorient the device, however hard it shakes it.
struct AttitudeGate {
    private let maxAngularChangeRadians: Double
    private var previousAttitude: Quaternion?

    init(maxAngularChangeDegrees: Double = 2.0) {
        self.maxAngularChangeRadians = maxAngularChangeDegrees * .pi / 180
    }

    /// `true` means the gate is open (this sample is trustworthy). The very first
    /// sample always passes — there's no prior attitude to compare against yet.
    mutating func evaluate(_ attitude: Quaternion) -> Bool {
        defer { previousAttitude = attitude }
        guard let previous = previousAttitude else { return true }
        return Self.angularDifference(previous, attitude) <= maxAngularChangeRadians
    }

    /// The rotation angle between two unit quaternions, via the standard
    /// `2·acos(|q1·q2|)` identity. `abs` accounts for quaternion double-cover — `q`
    /// and `-q` represent the identical rotation, and without it a coincidentally
    /// negated (but physically unchanged) attitude sample would read as a ~180°
    /// jump.
    static func angularDifference(_ a: Quaternion, _ b: Quaternion) -> Double {
        let dot = a.w * b.w + a.x * b.x + a.y * b.y + a.z * b.z
        let clamped = Swift.min(1, Swift.max(-1, abs(dot)))
        return 2 * acos(clamped)
    }
}
