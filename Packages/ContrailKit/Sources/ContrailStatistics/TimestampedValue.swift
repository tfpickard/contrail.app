import Foundation

/// One raw sample fed into a window tracker or peak detector.
public struct TimestampedValue: Sendable, Equatable {
    public let timestamp: Date
    public let value: Double

    public init(timestamp: Date, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}
