import Foundation

/// §4.1's approximate light/moderate/severe bands on the EDR^(1/3) scale airlines
/// and pilots use, "so the readout maps onto categories people already understand."
/// These are the commonly cited thresholds, not a derivation specific to this app's
/// uncalibrated measurement. Shared between the turbulence surface and photo caption
/// generation (§7.3) so both describe the same reading the same way.
public enum TurbulenceCategory: String, Sendable, Equatable {
    case smooth = "Smooth"
    case light = "Light"
    case moderate = "Moderate"
    case severe = "Severe"

    public init(edrCubeRoot edr: Double) {
        switch edr {
        case ..<0.1: self = .smooth
        case 0.1..<0.4: self = .light
        case 0.4..<0.7: self = .moderate
        default: self = .severe
        }
    }
}
