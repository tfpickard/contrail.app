/// ROADMAP 3a, verbatim: "strict two-stage disclosure. Advertising presence reveals
/// exactly one bit: someone here runs this app. Profile exchange is a separate
/// handshake requiring both parties to accept. Nobody learns anything about anybody
/// until both have said yes." This is that second stage's state, per peer.
public enum DisclosureState: Sendable, Equatable {
    /// Only the beacon's presence bit has been seen -- the default, and where every
    /// newly-sighted peer starts.
    case presenceOnly
    /// I've asked to exchange profiles; they haven't responded yet.
    case requestedByMe
    /// They've asked; I haven't responded yet.
    case requestedByThem
    /// Both sides have said yes -- the only state in which a profile handshake is
    /// permitted to actually happen.
    case mutuallyAccepted
}

/// The pure state machine `DisclosureState` transitions through. Two independent
/// "yes" events (mine, theirs) in either order both lead to `.mutuallyAccepted`;
/// neither one alone ever does.
public struct TwoStageDisclosure: Sendable, Equatable {
    public private(set) var state: DisclosureState

    public init(state: DisclosureState = .presenceOnly) {
        self.state = state
    }

    @discardableResult
    public mutating func requestByMe() -> DisclosureState {
        switch state {
        case .presenceOnly: state = .requestedByMe
        case .requestedByThem: state = .mutuallyAccepted
        case .requestedByMe, .mutuallyAccepted: break
        }
        return state
    }

    @discardableResult
    public mutating func requestByThem() -> DisclosureState {
        switch state {
        case .presenceOnly: state = .requestedByThem
        case .requestedByMe: state = .mutuallyAccepted
        case .requestedByThem, .mutuallyAccepted: break
        }
        return state
    }

    public var canExchangeProfile: Bool { state == .mutuallyAccepted }
}
