import Foundation

/// One candidate endpoint `IFEProber` tries, in order.
public struct IFEProbeTarget: Sendable, Equatable {
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

public extension IFEProbeTarget {
    /// ROADMAP 3b, verbatim: "no documentation exists, no stability is guaranteed,
    /// and the shape differs by vendor and by airline install." These addresses and
    /// paths come from public enthusiast/reverse-engineering write-ups about
    /// specific onboard portal installs (Panasonic and Thales/Rockwell Collins
    /// systems most commonly cited) -- **not** from vendor documentation this build
    /// has verified, and not tested against a real aircraft during this build. Every
    /// one of these is "worth trying," never "known to work." Extending this list —
    /// or replacing it entirely for a specific airline's known install — is the
    /// whole point of `IFEProber` being pluggable rather than hardcoded to one shape.
    static let knownTargets: [IFEProbeTarget] = [
        IFEProbeTarget(name: "Panasonic eXW moving map", url: URL(string: "http://11.0.0.1/data.json")!),
        IFEProbeTarget(name: "Panasonic gateway (alternate)", url: URL(string: "http://11.0.0.2/moving_map.json")!),
        IFEProbeTarget(name: "Thales/Rockwell Collins AVANT", url: URL(string: "http://192.168.1.1/api/v1/flightdata")!),
        IFEProbeTarget(name: "Global Eagle Ku-band portal", url: URL(string: "http://192.168.100.1/api/aircraft")!),
    ]
}
