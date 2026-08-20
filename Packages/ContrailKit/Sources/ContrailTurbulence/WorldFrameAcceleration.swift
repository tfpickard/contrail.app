import ContrailSensors

enum WorldFrameAcceleration {
    /// The component of `userAcceleration` along the local vertical, positive =
    /// upward — §4.1: "rotate user acceleration into the world frame using the
    /// attitude quaternion. Work on the vertical axis." Computed here as a dot
    /// product with the (negated) gravity vector instead: `gravity` is already
    /// CoreMotion's own device-frame unit vector pointing "down," so it *is* the
    /// local vertical axis — no quaternion rotation is needed for this specific
    /// extraction, and dotting against it is simpler and numerically identical to
    /// rotating the full acceleration vector and reading off its world-frame Z
    /// component. The attitude quaternion is still used, separately, by
    /// `AttitudeGate` — which genuinely needs to compare orientations over time,
    /// something a single gravity vector can't do.
    static func verticalComponent(userAcceleration: Vector3, gravity: Vector3) -> Double {
        -(userAcceleration.x * gravity.x + userAcceleration.y * gravity.y + userAcceleration.z * gravity.z)
    }
}
