import Testing
import ContrailSensors
@testable import ContrailTurbulence

struct WorldFrameAccelerationTests {
    @Test func gravityStraightDownGivesZAccelerationDirectly() {
        // Device flat on a table: gravity points straight down the device's Z axis.
        let gravity = Vector3(x: 0, y: 0, z: -1)
        let upwardAcceleration = Vector3(x: 0, y: 0, z: 2)
        let vertical = WorldFrameAcceleration.verticalComponent(userAcceleration: upwardAcceleration, gravity: gravity)
        #expect(abs(vertical - 2) < 1e-9)
    }

    @Test func horizontalAccelerationContributesNothingWhenGravityIsVertical() {
        let gravity = Vector3(x: 0, y: 0, z: -1)
        let sidewaysAcceleration = Vector3(x: 5, y: 3, z: 0)
        let vertical = WorldFrameAcceleration.verticalComponent(userAcceleration: sidewaysAcceleration, gravity: gravity)
        #expect(abs(vertical) < 1e-9)
    }

    @Test func tiltedDeviceProjectsOntoTheActualGravityAxis() {
        // Gravity pointing along device X (phone on its side) -- acceleration along
        // device X is "vertical" in this orientation, not device Z.
        let gravity = Vector3(x: -1, y: 0, z: 0)
        let accelerationAlongX = Vector3(x: 3, y: 0, z: 0)
        let vertical = WorldFrameAcceleration.verticalComponent(userAcceleration: accelerationAlongX, gravity: gravity)
        #expect(abs(vertical - 3) < 1e-9)
    }
}
