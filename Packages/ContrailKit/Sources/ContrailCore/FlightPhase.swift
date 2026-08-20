/// §3: the phase classifier's output. Drives per-phase logging floor rates and is the
/// strongest available signal for imminent descent (via pressurization rate, in
/// `CabinEnvironment`), which typically leads the cabin announcement.
public enum FlightPhase: String, Sendable, Codable, CaseIterable {
    case taxi, takeoff, climb, cruise, descent, landing
}
