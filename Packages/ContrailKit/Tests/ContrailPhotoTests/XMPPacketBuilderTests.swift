import Testing
@testable import ContrailPhoto

struct XMPPacketBuilderTests {
    @Test func buildsAWellFormedPacketWrappingTheJSON() {
        let json = #"{"altitude":11582.4,"phase":"cruise"}"#
        let packet = XMPPacketBuilder.buildPacket(jsonSnapshot: json)

        #expect(packet.contains("<?xpacket begin="))
        #expect(packet.contains("<?xpacket end=\"w\"?>"))
        #expect(packet.contains("x:xmpmeta"))
        #expect(packet.contains("rdf:RDF"))
        #expect(packet.contains(XMPPacketBuilder.namespaceURI))
        #expect(packet.contains(json))
    }

    @Test func extractSnapshotRoundTripsOrdinaryJSON() {
        let json = #"{"a":1,"b":[1,2,3],"c":"text with \"quotes\""}"#
        let packet = XMPPacketBuilder.buildPacket(jsonSnapshot: json)
        #expect(XMPPacketBuilder.extractSnapshot(fromPacket: packet) == json)
    }

    @Test func extractSnapshotRoundTripsJSONContainingTheCDATATerminator() {
        // A pathological but legal JSON string value containing the literal "]]>"
        // sequence, which would otherwise prematurely close the CDATA section.
        let json = #"{"weird":"a]]>b"}"#
        let packet = XMPPacketBuilder.buildPacket(jsonSnapshot: json)
        #expect(XMPPacketBuilder.extractSnapshot(fromPacket: packet) == json)
    }

    @Test func extractSnapshotReturnsNilWhenNoCDATAPresent() {
        #expect(XMPPacketBuilder.extractSnapshot(fromPacket: "<x:xmpmeta></x:xmpmeta>") == nil)
    }
}
