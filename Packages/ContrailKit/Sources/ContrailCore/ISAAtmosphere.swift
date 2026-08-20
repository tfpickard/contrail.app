import Foundation

/// The International Standard Atmosphere barometric formula, troposphere only
/// (below 11 km — every commercial cruise altitude). Used both directions: forward
/// by `ContrailSensors.SyntheticFlightLog` to synthesize a plausible cabin pressure
/// trace, and inverse by `ContrailEstimator` to turn a measured cabin pressure into
/// a pressure altitude (§2.3's `CabinEnvironment.pressureAltitude`) and, from its
/// rate of change, the pressurization-rate channel that's the strongest early
/// descent signal (§3).
public enum ISAAtmosphere {
    private static let seaLevelPressureKPa = 101.325
    private static let seaLevelTemperatureK = 288.15
    private static let lapseRate = 0.0065        // K/m
    private static let gravity = 9.80665          // m/s²
    private static let molarMassAir = 0.0289644   // kg/mol
    private static let gasConstant = 8.3144598     // J/(mol·K)

    private static var exponent: Double {
        (gravity * molarMassAir) / (gasConstant * lapseRate)
    }

    /// Pressure at a given altitude, kPa.
    public static func pressureKPa(altitude: Double) -> Double {
        seaLevelPressureKPa * pow(1 - (lapseRate * altitude) / seaLevelTemperatureK, exponent)
    }

    /// Altitude at a given pressure, metres. Inverse of `pressureKPa(altitude:)`.
    public static func altitude(pressureKPa: Double) -> Double {
        (seaLevelTemperatureK / lapseRate)
            * (1 - pow(pressureKPa / seaLevelPressureKPa, 1 / exponent))
    }
}
