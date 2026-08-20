import Foundation

/// RMS over the trailing `windowDuration`, via a running sum of squares. Uses a
/// plain array with O(n) `removeFirst` on eviction rather than `ContrailStatistics`'s
/// `RingDeque` machinery — deliberately: this window is a few seconds (tens to a few
/// hundred samples), not the 30-minute window §2.4 specifically warns an O(n)
/// rescan would "destroy the battery" over. A small bounded array eviction here is
/// genuinely fine, and pulling in a whole second package for one sliding sum isn't
/// worth the coupling.
struct SlidingRMS {
    private var buffer: [(timestamp: Date, value: Double)] = []
    private let windowDuration: TimeInterval
    private var sumOfSquares: Double = 0

    init(windowDuration: TimeInterval) {
        self.windowDuration = windowDuration
    }

    @discardableResult
    mutating func insert(_ timestamp: Date, _ value: Double) -> Double {
        buffer.append((timestamp, value))
        sumOfSquares += value * value

        let cutoff = timestamp.addingTimeInterval(-windowDuration)
        while let first = buffer.first, first.timestamp < cutoff {
            sumOfSquares -= first.value * first.value
            buffer.removeFirst()
        }

        guard !buffer.isEmpty else { return 0 }
        return Swift.max(0, sumOfSquares / Double(buffer.count)).squareRoot()
    }

    var sampleCount: Int { buffer.count }
}
