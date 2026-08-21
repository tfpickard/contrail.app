import Foundation
import Testing
import ContrailCore
@testable import ContrailData

struct NavFixIndexTests {
    private let dvvFix = NavFixRecord(
        id: "DVV", kind: .fix, navaidType: nil, name: nil,
        coordinate: Coordinate(latitude: 39.8, longitude: -104.9),
        artccHigh: "ZDV", artccLow: "ZDV", frequency: nil
    )
    private let denNavaid = NavFixRecord(
        id: "DEN", kind: .navaid, navaidType: "VORTAC", name: "DENVER",
        coordinate: Coordinate(latitude: 39.85, longitude: -104.65),
        artccHigh: "ZDV", artccLow: "ZDV", frequency: 117.9
    )

    @Test func nearestFindsTheClosestRecordRegardlessOfKind() {
        let index = NavFixIndex(records: [dvvFix, denNavaid])
        let nearDenver = Coordinate(latitude: 39.84, longitude: -104.66)
        #expect(index.nearest(to: nearDenver)?.id == "DEN")
    }

    @Test func compileThenReadRoundTrips() throws {
        let originals = [dvvFix, denNavaid]
        let data = NavFixIndex.compile(records: originals)
        let index = try NavFixIndex(data: data)
        #expect(index.count == 2)
        #expect(index.records.contains(dvvFix))
        #expect(index.records.contains(denNavaid))
    }

    @Test func roundTripPreservesNavaidFrequencyAndPlainFixLackThereof() throws {
        let data = NavFixIndex.compile(records: [dvvFix, denNavaid])
        let index = try NavFixIndex(data: data)
        let fix = try #require(index.records.first { $0.id == "DVV" })
        let navaid = try #require(index.records.first { $0.id == "DEN" })
        #expect(fix.frequency == nil)
        #expect(navaid.frequency == 117.9)
        #expect(navaid.navaidType == "VORTAC")
        #expect(navaid.name == "DENVER")
    }

    @Test func readingWrongDatasetKindThrows() {
        let placeData = PlaceIndex.compile(records: [])
        #expect(throws: (any Error).self) {
            _ = try NavFixIndex(data: placeData)
        }
    }
}
