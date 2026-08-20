import Foundation
import Testing
import ContrailCore
@testable import ContrailData

struct PlaceIndexTests {
    private let ely = PlaceRecord(
        name: "Ely", coordinate: Coordinate(latitude: 39.24744, longitude: -114.88863),
        countryCode: "US", admin1Code: "NV", population: 4134
    )
    private let denver = PlaceRecord(
        name: "Denver", coordinate: Coordinate(latitude: 39.7392, longitude: -104.9903),
        countryCode: "US", admin1Code: "CO", population: 715_522
    )
    private let london = PlaceRecord(
        name: "London", coordinate: Coordinate(latitude: 51.5074, longitude: -0.1278),
        countryCode: "GB", admin1Code: "ENG", population: 8_961_989
    )

    @Test func displayNameUsesFullUSStateNames() {
        #expect(ely.displayName == "Ely, Nevada")
        #expect(denver.displayName == "Denver, Colorado")
    }

    @Test func displayNameFallsBackToCountryCodeOutsideTheUS() {
        #expect(london.displayName == "London, GB")
    }

    // §5.6's own motivating case: over the Great Basin, the nearest city may be
    // dozens of miles away, and it must be reported with bearing and distance, not
    // just a name.
    @Test func nearestPlaceLookupReturnsElyWithBearingAndDistanceOverTheGreatBasin() {
        let index = PlaceIndex(records: [ely, denver, london])
        let lookup = index.nearestPlaceLookup()
        let query = Coordinate(latitude: 39.3, longitude: -115.0)
        let result = lookup(query)

        #expect(result?.name == "Ely, Nevada")
        #expect(result!.distance > 0)
        #expect(result!.distance < 50_000)
        #expect(result!.bearing >= 0 && result!.bearing < 360)
    }

    @Test func compileThenReadRoundTrips() throws {
        let originals = [ely, denver, london]
        let data = PlaceIndex.compile(records: originals)
        let index = try PlaceIndex(data: data)

        let recovered = index.nearest(to: ely.coordinate)
        #expect(recovered?.name == ely.name)
        #expect(recovered?.population == ely.population)
        #expect(recovered?.admin1Code == ely.admin1Code)
    }
}
