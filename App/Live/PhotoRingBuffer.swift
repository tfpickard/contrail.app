import Foundation
import ContrailCore

/// §7.1: "capture against the ring buffer, not the instant. Grab a window of
/// roughly ten seconds before and after the shutter, so a photo of a rough patch
/// carries the actual acceleration trace around it." Fed one `EstimatorOutput` at a
/// time from `AppModel.handle`, trimmed to a fixed retention window on every
/// append -- deliberately simple (a plain array, not `ContrailStatistics`' ring
/// buffers) since this only needs "everything from the last ~20 seconds," not
/// per-channel windowed statistics.
@MainActor
final class PhotoRingBuffer {
    private var samples: [(uptime: TimeInterval, output: EstimatorOutput)] = []
    private let retention: TimeInterval

    /// Retention comfortably covers pre-shutter (10s) and the post-shutter wait
    /// (10s) with margin, so a capture started right as the buffer is trimmed still
    /// has its full pre-window.
    init(retention: TimeInterval = 25) {
        self.retention = retention
    }

    func append(_ output: EstimatorOutput) {
        samples.append((output.uptime, output))
        let cutoff = output.uptime - retention
        if let firstKeptIndex = samples.firstIndex(where: { $0.uptime >= cutoff }) {
            samples.removeFirst(firstKeptIndex)
        } else {
            samples.removeAll()
        }
    }

    /// Every sample with uptime in `[centerUptime - halfWidth, centerUptime + halfWidth]`.
    /// For the post-shutter half of the window, the caller waits for real time to
    /// pass (and keeps calling `append`) before calling this -- the buffer can only
    /// return samples that have actually arrived.
    func window(around centerUptime: TimeInterval, halfWidth: TimeInterval) -> [EstimatorOutput] {
        samples
            .filter { abs($0.uptime - centerUptime) <= halfWidth }
            .map(\.output)
    }

    func reset() {
        samples.removeAll()
    }
}
