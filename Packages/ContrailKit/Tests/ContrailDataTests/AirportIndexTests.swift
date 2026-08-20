import Foundation
import Testing
import ContrailCore
@testable import ContrailData

struct AirportIndexTests {
    private let denver = AirportRecord(
        icao: "KDEN", iata: "DEN", name: "Denver International Airport", kind: .largeAirport,
        coordinate: Coordinate(latitude: 39.8617, longitude: -104.6731),
        elevationMetres: 1655, municipality: "Denver", isoCountry: "US"
    )
    private let losAngeles = AirportRecord(
        icao: "KLAX", iata: "LAX", name: "Los Angeles International Airport", kind: .largeAirport,
        coordinate: Coordinate(latitude: 33.9416, longitude: -118.4085),
        elevationMetres: 38, municipality: "Los Angeles", isoCountry: "US"
    )
    private let noIATA = AirportRecord(
        icao: "KAPA", iata: nil, name: "Centennial Airport", kind: .mediumAirport,
        coordinate: Coordinate(latitude: 39.5701, longitude: -104.8489),
        elevationMetres: 1793, municipality: "Denver", isoCountry: "US"
    )

    @Test func looksUpByICAOAndIATA() {
        let index = AirportIndex(records: [denver, losAngeles, noIATA])
        #expect(index.airport(icao: "KDEN")?.name == denver.name)
        #expect(index.airport(iata: "LAX")?.name == losAngeles.name)
        #expect(index.airport(icao: "kden")?.name == denver.name) // case-insensitive
        #expect(index.airport(iata: "APA") == nil) // no IATA on this record
        #expect(index.airport(icao: "ZZZZ") == nil)
    }

    @Test func nearestFindsTheClosestAirport() {
        let index = AirportIndex(records: [denver, losAngeles, noIATA])
        let nearCentennial = Coordinate(latitude: 39.57, longitude: -104.85)
        #expect(index.nearest(to: nearCentennial)?.icao == "KAPA")
    }

    @Test func compileThenReadRoundTrips() throws {
        let originals = [denver, losAngeles, noIATA]
        let data = AirportIndex.compile(records: originals)
        let index = try AirportIndex(data: data)

        #expect(index.count == originals.count)
        let recovered = index.airport(icao: "KDEN")
        #expect(recovered?.name == denver.name)
        #expect(recovered?.iata == denver.iata)
        #expect(recovered?.kind == denver.kind)
        #expect(recovered?.coordinate.latitude == denver.coordinate.latitude)
        #expect(recovered?.elevationMetres == denver.elevationMetres)

        let noIATARecovered = index.airport(icao: "KAPA")
        #expect(noIATARecovered?.iata == nil)
    }

    @Test func readingWrongKindThrows() {
        let placeIndexData = PlaceIndex.compile(records: [
            PlaceRecord(name: "Ely", coordinate: Coordinate(latitude: 39.25, longitude: -114.89),
                        countryCode: "US", admin1Code: "NV", population: 4134)
        ])
        #expect(throws: (any Error).self) {
            try AirportIndex(data: placeIndexData)
        }
    }
}
