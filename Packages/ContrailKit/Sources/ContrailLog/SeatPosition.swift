/// ROADMAP Phase 4: "whether your seat relative to the wing measurably changes what
/// you feel -- which it does, and now you can prove it." Nothing on the phone can
/// detect where in the cabin it is, so this is entered once at the gate, the same
/// honest-manual-entry pattern §5.1 already uses for flight number and airports --
/// self-reported, never inferred, and optional (a flight logged before this field
/// existed, or a user who skips it, just has one fewer axis to compare later).
public enum SeatPosition: String, Sendable, Codable, Equatable, CaseIterable {
    case forward = "forward"
    case overWing = "over_wing"
    case aft = "aft"

    public var displayName: String {
        switch self {
        case .forward: return "Forward of wing"
        case .overWing: return "Over the wing"
        case .aft: return "Aft of wing"
        }
    }
}
