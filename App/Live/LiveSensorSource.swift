import Foundation
import CoreLocation
import CoreMotion
import ContrailCore
import ContrailSensors

/// The live `SensorSource` conformance (§2.2): CoreLocation, CoreMotion, and
/// CMAltimeter, unified into one `AsyncStream`. `ReplaySensorSource` (ContrailKit)
/// is this type's desk-testing counterpart — both conform to the same protocol, so
/// nothing downstream of `SensorSource` knows or cares which one is producing.
///
/// **Verification note:** this file type-checks and compiles against the iOS SDK,
/// but GPS/motion/barometer hardware isn't available in the iOS Simulator and this
/// session has no physical device attached — its actual runtime behavior is
/// unverified. `ReplaySensorSource` carries the real test coverage.
final class LiveSensorSource: NSObject, SensorSource, @unchecked Sendable {
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let locationManager = CLLocationManager()

    /// §3: device motion runs high and fixed — the cheapest sensor on the device,
    /// and the trigger mechanism 1.2's (deferred) turbulence burst capture needs.
    private let motionUpdateInterval: TimeInterval = 1.0 / 50.0

    /// A dedicated serial queue for CoreMotion/CMAltimeter callback delivery — the
    /// plan's own concurrency design ("one dedicated serial queue... the single
    /// writer") kept off the main queue. CLLocationUpdate's async sequence delivers
    /// via its own Swift concurrency executor and doesn't use this queue.
    private let sensorQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    func samples() -> AsyncStream<RawSensorSample> {
        AsyncStream { continuation in
            configureLocationManager()

            let locationTask = Task {
                await streamLocationUpdates(into: continuation)
            }

            startMotionUpdates(into: continuation)
            startAltimeterUpdates(into: continuation)

            // Captures `self`, not the individual CMMotionManager/CMAltimeter
            // properties directly — those Apple types aren't Sendable, but this
            // type's own `@unchecked Sendable` conformance is the deliberate,
            // reviewed trust boundary; destructuring into `[motionManager, altimeter]`
            // would re-trigger per-property checking the class-level annotation
            // already covers.
            continuation.onTermination = { [self] _ in
                locationTask.cancel()
                motionManager.stopDeviceMotionUpdates()
                if CMAltimeter.isRelativeAltitudeAvailable() {
                    altimeter.stopRelativeAltitudeUpdates()
                }
            }
        }
    }

    // MARK: - CoreLocation

    private func configureLocationManager() {
        // §6's background-logging requirement (pushback #5): both this flag AND the
        // Info.plist `UIBackgroundModes: [location]` entry are required together —
        // neither alone does anything.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.activityType = .airborne

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestAlwaysAuthorization()
        }
    }

    private func streamLocationUpdates(into continuation: AsyncStream<RawSensorSample>.Continuation) async {
        do {
            // `.airborne` is CoreLocation's own configuration for exactly this use
            // case — aircraft-appropriate update behavior, not general navigation.
            for try await update in CLLocationUpdate.liveUpdates(.airborne) {
                guard !Task.isCancelled else { return }
                guard let location = update.location else { continue }
                continuation.yield(.location(LocationSample(
                    timestamp: location.timestamp,
                    coordinate: Coordinate(
                        latitude: location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    ),
                    altitude: location.ellipsoidalAltitude,
                    horizontalAccuracy: location.horizontalAccuracy,
                    verticalAccuracy: location.verticalAccuracy,
                    // CoreLocation's own sentinel for "invalid": negative values.
                    // §2.2: carried separately, never fused into computed groundspeed/course.
                    speed: location.speed >= 0 ? location.speed : nil,
                    course: location.course >= 0 ? location.course : nil
                )))
            }
        } catch {
            // The live-updates sequence ended (authorization revoked, etc.). The
            // location half of the stream simply stops; motion/pressure continue —
            // there is no single fatal error for the whole `SensorSource`.
        }
    }

    // MARK: - CoreMotion

    private func startMotionUpdates(into continuation: AsyncStream<RawSensorSample>.Continuation) {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = motionUpdateInterval
        motionManager.startDeviceMotionUpdates(to: sensorQueue) { motion, _ in
            guard let motion else { return }
            continuation.yield(.motion(MotionSample(
                timestamp: Self.wallClockDate(fromSensorTimestamp: motion.timestamp),
                userAcceleration: Vector3(
                    x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z
                ),
                gravity: Vector3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
                attitude: Quaternion(
                    x: motion.attitude.quaternion.x, y: motion.attitude.quaternion.y,
                    z: motion.attitude.quaternion.z, w: motion.attitude.quaternion.w
                ),
                rotationRate: Vector3(
                    x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z
                )
            )))
        }
    }

    // MARK: - CMAltimeter

    private func startAltimeterUpdates(into continuation: AsyncStream<RawSensorSample>.Continuation) {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: sensorQueue) { data, _ in
            guard let data else { return }
            continuation.yield(.pressure(PressureSample(
                timestamp: Self.wallClockDate(fromSensorTimestamp: data.timestamp),
                // CMAltitudeData.pressure is in kPa already.
                kilopascals: data.pressure.doubleValue
            )))
        }
    }

    // MARK: - Timestamp conversion

    /// CoreMotion/CMAltimeter timestamps are seconds since device boot
    /// (`systemUptime`-relative), not Unix epoch or `Date`'s reference date. Mixing
    /// that convention with `LocationSample.timestamp` (a real wall-clock `Date`,
    /// straight from CoreLocation) without converting would silently corrupt every
    /// downstream time delta the estimator computes.
    private static func wallClockDate(fromSensorTimestamp sensorTimestamp: TimeInterval) -> Date {
        let uptimeNow = ProcessInfo.processInfo.systemUptime
        return Date().addingTimeInterval(sensorTimestamp - uptimeNow)
    }
}
