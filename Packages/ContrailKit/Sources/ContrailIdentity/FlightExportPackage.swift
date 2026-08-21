import Foundation
import ContrailCore
import ContrailLog

/// The unit of exchange for a group flight record. ROADMAP Phase 2 -- Identity:
/// "several people... each running the app, producing one combined record" -- but
/// with Phase 3's local-discovery transport not yet built, the only way for two
/// phones to combine a flight in this phase is to hand each other a file: AirDrop,
/// Messages, Files, whatever the share sheet offers. This is that file's contents,
/// self-describing and independent of any particular transport.
public struct FlightExportPackage: Sendable, Codable, Equatable {
    public let schema: SchemaVersion
    /// Who logged this -- `UserProfile.displayName` at export time, or a fallback if
    /// the exporter never filled one in. Deliberately just a display string, not an
    /// account identifier: there is no account system in this build, and a group
    /// flight record's whole point is to work between phones that have never talked
    /// to each other before.
    public let participantName: String
    public let manifest: FlightManifest
    public let records: [LogRecord]

    public init(participantName: String, manifest: FlightManifest, records: [LogRecord], schema: SchemaVersion = .current) {
        self.schema = schema
        self.participantName = participantName
        self.manifest = manifest
        self.records = records
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> FlightExportPackage {
        try JSONDecoder().decode(FlightExportPackage.self, from: data)
    }
}
