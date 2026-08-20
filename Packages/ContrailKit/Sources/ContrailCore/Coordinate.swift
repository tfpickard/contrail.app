/// A WGS-84 geographic coordinate. Degrees, not radians — conversion happens at the
/// point of use in ContrailGeo, keeping this type a plain data carrier with no
/// trigonometry dependency.
public struct Coordinate: Sendable, Codable, Equatable {
    public let latitude: Double   // degrees, +N
    public let longitude: Double  // degrees, +E

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A place with its bearing and distance from the current position. §5.6: "nearest
/// city" must never be reported as a bare name — over the Great Basin the nearest
/// city may be 90 miles away, and "near Ely, Nevada" alone is a lie.
public struct BearingToPlace: Sendable, Codable, Equatable {
    public let name: String
    public let bearing: Double    // degrees true, 0..<360
    public let distance: Double   // metres

    public init(name: String, bearing: Double, distance: Double) {
        self.name = name
        self.bearing = bearing
        self.distance = distance
    }
}
