import Foundation
import ContrailCore
import ContrailData

/// §7.3's generated text -- exact shapes:
/// - Title: `Denver (DEN) to Los Angeles (LAX), August 20 -- over Provo, Utah, cruise`
/// - Description: `38,000 ft, 511 kt ground, smooth. 42 mi N of Ely, Nevada.`
///
/// The title deliberately omits anything that changes photo-to-photo besides
/// location/phase (no clock time, no percentage, per the spec) -- every photo from
/// the same flight shares the same route/date prefix, "which makes the flight
/// function as a de facto searchable album in Photos."
public enum PhotoCaptionGenerator {
    public static func title(
        origin: AirportRecord, destination: AirportRecord, departureDate: Date,
        nearestCity: BearingToPlace?, phase: FlightPhase?
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d"
        let date = dateFormatter.string(from: departureDate)

        var title = "\(cityName(origin)) (\(airportCode(origin))) to " +
            "\(cityName(destination)) (\(airportCode(destination))), \(date)"

        if let nearestCity {
            title += " — over \(nearestCity.name)"
        }
        if let phase {
            title += ", \(phase.rawValue)"
        }
        return title
    }

    public static func description(
        altitudeMetres: Double?, groundspeedMS: Double?, edrCubeRoot: Double?, nearestCity: BearingToPlace?
    ) -> String {
        var parts: [String] = []

        if let altitudeMetres {
            let feet = (altitudeMetres * 3.28084 / 100).rounded() * 100
            parts.append("\(Self.formatted(feet)) ft")
        }
        if let groundspeedMS {
            let knots = (groundspeedMS * 1.943_844).rounded()
            parts.append("\(Self.formatted(knots)) kt ground")
        }
        if let edrCubeRoot {
            parts.append(TurbulenceCategory(edrCubeRoot: edrCubeRoot).rawValue.lowercased())
        }

        var description = parts.joined(separator: ", ")

        if let nearestCity {
            let miles = (nearestCity.distance / 1609.344).rounded()
            let compass = compassAbbreviation(forBearing: nearestCity.bearing)
            let sentence = "\(Self.formatted(miles)) mi \(compass) of \(nearestCity.name)"
            description = description.isEmpty ? sentence : "\(description). \(sentence)."
        } else if !description.isEmpty {
            description += "."
        }

        return description
    }

    private static func cityName(_ airport: AirportRecord) -> String {
        airport.municipality.isEmpty ? airport.name : airport.municipality
    }

    private static func airportCode(_ airport: AirportRecord) -> String {
        airport.iata ?? airport.icao
    }

    private static func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
    }

    /// 16-point compass rose -- finer than the 8-point/N-E-S-W-only rose, since the
    /// spec's own example ("42 mi N of Ely, Nevada") is a single-letter cardinal but
    /// doesn't preclude a more precise intercardinal reading when the actual bearing
    /// calls for one.
    private static func compassAbbreviation(forBearing bearing: Double) -> String {
        let points = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
        ]
        let normalized = bearing.truncatingRemainder(dividingBy: 360)
        let index = Int(((normalized < 0 ? normalized + 360 : normalized) / 22.5).rounded()) % 16
        return points[index]
    }
}
