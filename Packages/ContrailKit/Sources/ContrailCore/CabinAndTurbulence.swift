/// §2.3 cabin environment. `pressure` is **cabin** pressure from CMAltimeter, not
/// ambient — CMAltimeter cannot measure outside the pressure vessel.
public struct CabinEnvironment: Sendable, Codable, Equatable {
    public let pressure: Channel<Double>               // kPa, cabin
    public let pressureAltitude: Channel<Double>        // metres, ISA-derived from cabin pressure
    public let pressurizationRate: Channel<Double>      // m/s — strongest early descent signal

    public init(
        pressure: Channel<Double>,
        pressureAltitude: Channel<Double>,
        pressurizationRate: Channel<Double>
    ) {
        self.pressure = pressure
        self.pressureAltitude = pressureAltitude
        self.pressurizationRate = pressurizationRate
    }
}

/// §4.1/§4.2. Both channels report `.unavailable` in Phase 1.0 — measurement ships in
/// 1.2, forecast in 1.6 — but the shape exists now so 1.6 never has to migrate a log.
/// Same unit on both sides (EDR^(1/3), m^(2/3)/s) is deliberate: it is what makes the
/// predicted-vs-measured comparison (§4.3) a direct subtraction.
public struct TurbulenceEstimate: Sendable, Codable, Equatable {
    public let edrCubeRoot: Channel<Double>             // m^(2/3)/s — measured, 1.2
    public let forecastEdrCubeRoot: Channel<Double>     // m^(2/3)/s — GTG, 1.6
    public let attitudeGateOpen: Channel<Bool>          // §4.1 handling-motion discriminator state

    public init(
        edrCubeRoot: Channel<Double>,
        forecastEdrCubeRoot: Channel<Double>,
        attitudeGateOpen: Channel<Bool>
    ) {
        self.edrCubeRoot = edrCubeRoot
        self.forecastEdrCubeRoot = forecastEdrCubeRoot
        self.attitudeGateOpen = attitudeGateOpen
    }

    /// All three channels `.unavailable` — the value 1.0 ships until 1.2 lands.
    public static let unavailable = TurbulenceEstimate(
        edrCubeRoot: .unavailable,
        forecastEdrCubeRoot: .unavailable,
        attitudeGateOpen: .unavailable
    )
}
