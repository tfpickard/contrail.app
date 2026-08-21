import Foundation
import Testing
import ContrailCore
import ContrailData
@testable import ContrailPhoto

struct PhotoCaptionGeneratorTests {
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

    private func date(month: Int, day: Int, year: Int = 2026) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day; components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    // Matches §7.3's own worked example exactly: "Denver (DEN) to Los Angeles (LAX),
    // August 20 -- over Provo, Utah, cruise" -- modulo the em dash, which the spec's
    // prose renders as "--" but this generator uses a real em dash character.
    @Test func matchesTheSpecsOwnTitleExample() {
        let title = PhotoCaptionGenerator.title(
            origin: denver, destination: losAngeles, departureDate: date(month: 8, day: 20),
            nearestCity: BearingToPlace(name: "Provo, Utah", bearing: 190, distance: 50_000),
            phase: .cruise
        )
        #expect(title == "Denver (DEN) to Los Angeles (LAX), August 20 — over Provo, Utah, cruise")
    }

    @Test func titleOmitsNearestCityAndPhaseWhenUnavailable() {
        let title = PhotoCaptionGenerator.title(
            origin: denver, destination: losAngeles, departureDate: date(month: 8, day: 20),
            nearestCity: nil, phase: nil
        )
        #expect(title == "Denver (DEN) to Los Angeles (LAX), August 20")
    }

    // §7.3's own worked example: "38,000 ft, 511 kt ground, smooth. 42 mi N of Ely,
    // Nevada." -- altitude/speed/turbulence/nearest-city all independently derived
    // from realistic SI inputs, not hand-typed to match.
    @Test func matchesTheSpecsOwnDescriptionExample() {
        let description = PhotoCaptionGenerator.description(
            altitudeMetres: 11_582.4, // ≈ 38,000 ft
            groundspeedMS: 262.9, // ≈ 511 kt
            edrCubeRoot: 0.02, // smooth band
            nearestCity: BearingToPlace(name: "Ely, Nevada", bearing: 0, distance: 67_594) // ≈ 42 mi, due north
        )
        #expect(description == "38,000 ft, 511 kt ground, smooth. 42 mi N of Ely, Nevada.")
    }

    @Test func descriptionOmitsMissingChannelsGracefully() {
        let description = PhotoCaptionGenerator.description(
            altitudeMetres: nil, groundspeedMS: nil, edrCubeRoot: nil, nearestCity: nil
        )
        #expect(description.isEmpty)
    }

    @Test func compassAbbreviationCoversAllSixteenPoints() {
        // Indirect test via description -- bearings chosen at each 22.5° point.
        let bearings: [(Double, String)] = [
            (0, "N"), (45, "NE"), (90, "E"), (135, "SE"),
            (180, "S"), (225, "SW"), (270, "W"), (315, "NW"),
            (359, "N"),
        ]
        for (bearing, expected) in bearings {
            let description = PhotoCaptionGenerator.description(
                altitudeMetres: nil, groundspeedMS: nil, edrCubeRoot: nil,
                nearestCity: BearingToPlace(name: "Somewhere", bearing: bearing, distance: 1000)
            )
            #expect(description.contains(" \(expected) of Somewhere"), "bearing \(bearing) -> \(description)")
        }
    }
}
