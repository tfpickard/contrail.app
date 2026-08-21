import ContrailCore

/// §5.4: one ARTCC's jurisdiction boundary at one altitude tier (FAA NASR publishes
/// separate `HIGH`/`LOW`/`UNLIMITED` polygons per center — a position can be inside
/// a different center's boundary depending on altitude). `vertices` is the polygon
/// FAA NASR's `ARB_SEG` gives, in published order, connected edge-to-edge including
/// last-back-to-first (see `PointInPolygon`'s own doc comment on why that's a flat,
/// not geodesic, connection).
public struct ARTCCBoundary: Sendable, Equatable {
    public enum AltitudeTier: String, Sendable, Equatable {
        case low = "LOW"
        case high = "HIGH"
        case unlimited = "UNLIMITED"
    }

    public let id: String // e.g. "ZAB"
    public let name: String // e.g. "ALBUQUERQUE"
    public let altitudeTier: AltitudeTier
    public let vertices: [Coordinate]

    public init(id: String, name: String, altitudeTier: AltitudeTier, vertices: [Coordinate]) {
        self.id = id; self.name = name; self.altitudeTier = altitudeTier; self.vertices = vertices
    }
}

extension ARTCCBoundary {
    func write(to writer: inout BinaryDatasetWriter) {
        writer.writeString(id)
        writer.writeString(name)
        writer.writeString(altitudeTier.rawValue)
        writer.writeUInt16(UInt16(vertices.count))
        for vertex in vertices {
            writer.writeDouble(vertex.latitude)
            writer.writeDouble(vertex.longitude)
        }
    }

    static func read(from reader: inout BinaryDatasetReader) throws -> ARTCCBoundary {
        let id = try reader.readString()
        let name = try reader.readString()
        let tierRaw = try reader.readString()
        let vertexCount = Int(try reader.readUInt16())
        var vertices: [Coordinate] = []
        vertices.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            let latitude = try reader.readDouble()
            let longitude = try reader.readDouble()
            vertices.append(Coordinate(latitude: latitude, longitude: longitude))
        }
        return ARTCCBoundary(
            id: id, name: name,
            altitudeTier: ARTCCBoundary.AltitudeTier(rawValue: tierRaw) ?? .unlimited,
            vertices: vertices
        )
    }
}
