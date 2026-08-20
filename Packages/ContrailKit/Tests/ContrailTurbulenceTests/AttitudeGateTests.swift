import Foundation
import Testing
import ContrailSensors
@testable import ContrailTurbulence

struct AttitudeGateTests {
    private let identity = Quaternion(x: 0, y: 0, z: 0, w: 1)

    @Test func angularDifferenceOfIdenticalQuaternionsIsZero() {
        #expect(AttitudeGate.angularDifference(identity, identity) < 1e-9)
    }

    @Test func angularDifferenceOfNegatedQuaternionIsZeroNotPi() {
        // q and -q represent the same rotation (double-cover) -- must not read as a
        // ~180 degree jump.
        let negated = Quaternion(x: 0, y: 0, z: 0, w: -1)
        #expect(AttitudeGate.angularDifference(identity, negated) < 1e-9)
    }

    @Test func angularDifferenceOfA90DegreeRotationIsPiOverTwo() {
        // A 90-degree rotation about Z: quaternion (0, 0, sin(45deg), cos(45deg)).
        let angle = Double.pi / 2
        let ninetyAboutZ = Quaternion(x: 0, y: 0, z: sin(angle / 2), w: cos(angle / 2))
        let difference = AttitudeGate.angularDifference(identity, ninetyAboutZ)
        #expect(abs(difference - angle) < 1e-9)
    }

    @Test func firstSampleAlwaysPassesWithNoPriorHistory() {
        var gate = AttitudeGate(maxAngularChangeDegrees: 1)
        #expect(gate.evaluate(identity) == true)
    }

    @Test func staysOpenAcrossSmallStableChanges() {
        var gate = AttitudeGate(maxAngularChangeDegrees: 5)
        #expect(gate.evaluate(identity) == true)
        // A tiny 0.5-degree rotation about Z, well within the threshold.
        let angle = 0.5 * Double.pi / 180
        let tinyRotation = Quaternion(x: 0, y: 0, z: sin(angle / 2), w: cos(angle / 2))
        #expect(gate.evaluate(tinyRotation) == true)
    }

    @Test func closesOnALargeSuddenRotation() {
        var gate = AttitudeGate(maxAngularChangeDegrees: 2)
        #expect(gate.evaluate(identity) == true)
        // A 45-degree rotation -- the kind of change picking the phone up would
        // produce, well beyond the 2-degree threshold.
        let angle = 45 * Double.pi / 180
        let bigRotation = Quaternion(x: 0, y: 0, z: sin(angle / 2), w: cos(angle / 2))
        #expect(gate.evaluate(bigRotation) == false)
    }
}
