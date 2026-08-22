import Foundation
import Testing
import ContrailCore
import ContrailData
@testable import ContrailAnalytics

struct AirspaceHistoryCompilerTests {
    private let zabSquare: [Coordinate] = [
        Coordinate(latitude: 30, longitude: -110),
        Coordinate(latitude: 30, longitude: -100),
        Coordinate(latitude: 40, longitude: -100),
        Coordinate(latitude: 40, longitude: -110),
    ]
    private let zdvSquare: [Coordinate] = [
        Coordinate(latitude: 40, longitude: -110),
        Coordinate(latitude: 40, longitude: -100),
        Coordinate(latitude: 50, longitude: -100),
        Coordinate(latitude: 50, longitude: -110),
    ]

    private var index: ARTCCBoundaryIndex {
        ARTCCBoundaryIndex(boundaries: [
            ARTCCBoundary(id: "ZAB", name: "ALBUQUERQUE", altitudeTier: .high, vertices: zabSquare),
            ARTCCBoundary(id: "ZDV", name: "DENVER", altitudeTier: .high, vertices: zdvSquare),
        ])
    }

    @Test func findsEveryBoundaryVisitedAcrossAllFlights() {
        let base = Date(timeIntervalSince1970: 0)
        let insideZAB = Coordinate(latitude: 35, longitude: -105)
        let insideZDV = Coordinate(latitude: 45, longitude: -105)

        let flightA = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [makeSample(t: base, position: insideZAB, altitude: 11_000)]
        )
        let flightB = AnalyzedFlight(
            manifest: makeManifest(number: "UA2", date: "2026-08-08"),
            records: [makeSample(t: base, position: insideZDV, altitude: 11_000)]
        )

        let visited = AirspaceHistoryCompiler.compile(from: [flightA, flightB], artccIndex: index, sampleStride: 1)
        #expect(visited.map(\.id).sorted() == ["ZAB", "ZDV"])
    }

    @Test func deduplicatesRepeatedVisitsToTheSameBoundary() {
        let base = Date(timeIntervalSince1970: 0)
        let insideZAB = Coordinate(latitude: 35, longitude: -105)
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: (0..<5).map { i in
                makeSample(t: base.addingTimeInterval(Double(i) * 10), position: insideZAB, altitude: 11_000)
            }
        )
        let visited = AirspaceHistoryCompiler.compile(from: [flight], artccIndex: index, sampleStride: 1)
        #expect(visited.count == 1)
    }

    @Test func positionsOutsideEveryBoundaryContributeNothing() {
        let base = Date(timeIntervalSince1970: 0)
        let farAway = Coordinate(latitude: 0, longitude: 0)
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: [makeSample(t: base, position: farAway, altitude: 11_000)]
        )
        #expect(AirspaceHistoryCompiler.compile(from: [flight], artccIndex: index, sampleStride: 1).isEmpty)
    }

    @Test func strideSkipsSamplesButStillFindsABoundaryVisitedThroughout() {
        let base = Date(timeIntervalSince1970: 0)
        let insideZAB = Coordinate(latitude: 35, longitude: -105)
        let flight = AnalyzedFlight(
            manifest: makeManifest(number: "UA1", date: "2026-08-01"),
            records: (0..<20).map { i in
                makeSample(t: base.addingTimeInterval(Double(i) * 10), position: insideZAB, altitude: 11_000)
            }
        )
        let visited = AirspaceHistoryCompiler.compile(from: [flight], artccIndex: index, sampleStride: 7)
        #expect(visited.map(\.id) == ["ZAB"])
    }
}
