/// §2.2: the boundary between the device's sensors and everything downstream.
/// `LiveSensorSource` (App target — wraps CoreLocation/CoreMotion/CMAltimeter) and
/// `ReplaySensorSource` (this package) are the two required conformances; a future
/// external-GNSS source (ROADMAP "Deferred / speculative") would be a third,
/// unmodified by anything that only knows this protocol.
public protocol SensorSource: Sendable {
    /// A single time-ordered stream of raw samples across every channel. Ends
    /// (`AsyncStream` finishes) when the source is exhausted — a replay reaching the
    /// end of its log — or when the consumer stops iterating, which tears down the
    /// underlying subscription via `onTermination`.
    func samples() -> AsyncStream<RawSensorSample>
}
