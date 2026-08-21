import Foundation

/// §7.2 tier 3: "an XMP block carrying the full structured snapshot as JSON." Builds
/// a real, spec-shaped XMP packet (Adobe's `<?xpacket?>` wrapper around an
/// `x:xmpmeta`/`rdf:RDF` document) rather than an ad-hoc text blob, so a generic XMP
/// reader can still parse the packet structure even though the payload itself
/// (Contrail's own `EstimatorOutput` JSON) isn't modeled as RDF properties -- the
/// spec's own wording asks for "the full structured snapshot as JSON," not a
/// property-by-property RDF re-encoding of it.
public enum XMPPacketBuilder {
    /// The custom namespace the JSON snapshot lives under, in `rdf:Description`.
    public static let namespaceURI = "http://contrail.app/ns/1.0/"
    public static let namespacePrefix = "contrail"

    /// Builds the full XMP packet, ready to embed as a JPEG APP1 segment's payload
    /// (see `JPEGSegmentInjector`). `jsonSnapshot` is expected to already be valid
    /// UTF-8 JSON text (typically `EstimatorOutput` encoded via `JSONEncoder`).
    public static func buildPacket(jsonSnapshot: String) -> String {
        // CDATA can hold arbitrary JSON as-is (no XML-entity escaping needed) except
        // for the literal terminator sequence "]]>", which JSON could in principle
        // contain inside a string value -- split it so the CDATA section can't be
        // prematurely closed by the payload itself.
        let safeJSON = jsonSnapshot.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")

        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Contrail 1.0">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:\(namespacePrefix)="\(namespaceURI)">
        <\(namespacePrefix):snapshot><![CDATA[\(safeJSON)]]></\(namespacePrefix):snapshot>
        <\(namespacePrefix):schemaVersion>1.0</\(namespacePrefix):schemaVersion>
        </rdf:Description>
        </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }

    /// The inverse of embedding: pulls the JSON snapshot back out of a full XMP
    /// packet string. Used by tests (and could back a future "read metadata back
    /// off a shared photo" feature) -- a plain substring scan between the CDATA
    /// markers, since this module doesn't carry a full XML parser.
    ///
    /// A naive first-match search for the closing `]]>` breaks on content that
    /// itself contained an escaped `]]>` (`buildPacket` rewrites it to
    /// `]]]]><![CDATA[>`, which contains a literal `]]>` substring partway through
    /// the escape sequence itself) -- this walks candidate closes and skips any
    /// immediately followed by a CDATA reopen, since that's the escape, not the
    /// real terminator.
    public static func extractSnapshot(fromPacket packet: String) -> String? {
        guard let openRange = packet.range(of: "<![CDATA[") else { return nil }
        let reopenTag = "<![CDATA["
        var searchStart = openRange.upperBound
        while let closeRange = packet.range(of: "]]>", range: searchStart..<packet.endIndex) {
            if packet[closeRange.upperBound...].hasPrefix(reopenTag) {
                searchStart = packet.index(closeRange.upperBound, offsetBy: reopenTag.count)
                continue
            }
            return String(packet[openRange.upperBound..<closeRange.lowerBound])
                .replacingOccurrences(of: "]]]]><![CDATA[>", with: "]]>")
        }
        return nil
    }
}
