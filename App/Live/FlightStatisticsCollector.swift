import Foundation
import ContrailCore
import ContrailStatistics

/// The app-specific channel set §2.4's statistics engine tracks. `ContrailStatistics`
/// itself is generic (any named `Double` channel, any window) and has no idea what
/// "groundspeed" or "cross-track error" means — this type is the glue that picks
/// which `EstimatorOutput` fields get windowed statistics and what physical range
/// each one's histogram should expect. Adding a sixth tracked channel is exactly the
/// "configuration, not new code" `ContrailStatistics` was built for: one more
/// property here, one more line in `ingest`.
final class FlightStatisticsCollector {
    let groundspeed = ChannelStatisticsTracker(expectedRange: 0...350)          // m/s, ~680 kt ceiling
    let verticalSpeed = ChannelStatisticsTracker(expectedRange: -50...50)       // m/s
    let crossTrackError = ChannelStatisticsTracker(expectedRange: -100_000...100_000) // m
    let cabinPressureAltitude = ChannelStatisticsTracker(expectedRange: -500...5_000)  // m
    let pressurizationRate = ChannelStatisticsTracker(expectedRange: -20...20)  // m/s

    func ingest(_ output: EstimatorOutput) {
        if let value = output.motion.groundspeed.value {
            groundspeed.insert(TimestampedValue(timestamp: output.t, value: value))
        }
        if let value = output.motion.verticalSpeed.value {
            verticalSpeed.insert(TimestampedValue(timestamp: output.t, value: value))
        }
        if let value = output.route.crossTrackError.value {
            crossTrackError.insert(TimestampedValue(timestamp: output.t, value: value))
        }
        if let value = output.cabin.pressureAltitude.value {
            cabinPressureAltitude.insert(TimestampedValue(timestamp: output.t, value: value))
        }
        if let value = output.cabin.pressurizationRate.value {
            pressurizationRate.insert(TimestampedValue(timestamp: output.t, value: value))
        }
    }

    var snapshot: FlightStatisticsSnapshot {
        FlightStatisticsSnapshot(
            groundspeed: groundspeed.allWindowStatistics,
            verticalSpeed: verticalSpeed.allWindowStatistics,
            crossTrackError: crossTrackError.allWindowStatistics,
            cabinPressureAltitude: cabinPressureAltitude.allWindowStatistics,
            pressurizationRate: pressurizationRate.allWindowStatistics
        )
    }
}

/// A `Sendable` snapshot of every tracked channel's statistics, all four windows —
/// what actually crosses from `FlightEstimationEngine`'s actor isolation out to the
/// `@MainActor` UI, at the throttled UI cadence (unlike the `ingest` calls above,
/// which happen at full sensor rate).
struct FlightStatisticsSnapshot: Sendable, Equatable {
    let groundspeed: AllWindowStatistics
    let verticalSpeed: AllWindowStatistics
    let crossTrackError: AllWindowStatistics
    let cabinPressureAltitude: AllWindowStatistics
    let pressurizationRate: AllWindowStatistics
}
