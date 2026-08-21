import Foundation
import ContrailCore

/// One decoded GTG forecast value: clear-air turbulence EDR^(1/3) (matching §4.1's
/// own measured metric exactly -- GribStream's `CATEDR` field is published in
/// m^(2/3)/s, the same unit EDR^(1/3) carries, not raw EDR, so no conversion is
/// needed to compare the two) at a specific point, altitude, and forecast valid time.
public struct ForecastSample: Sendable, Equatable {
    public let coordinate: Coordinate
    public let altitudeMetres: Double
    public let validTime: Date
    public let edrCubeRoot: Double

    public init(coordinate: Coordinate, altitudeMetres: Double, validTime: Date, edrCubeRoot: Double) {
        self.coordinate = coordinate
        self.altitudeMetres = altitudeMetres
        self.validTime = validTime
        self.edrCubeRoot = edrCubeRoot
    }
}
