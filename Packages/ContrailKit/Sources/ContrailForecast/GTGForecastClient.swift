import Foundation
import ContrailCore

/// A thin client for GribStream's documented forecast API
/// (`POST https://gribstream.com/api/v2/<model>/timeseries`, Bearer-token
/// authenticated), scoped to exactly the `dafsgtg` model's `CATEDR` (clear-air
/// turbulence EDR^(1/3)) variable this app needs.
///
/// **Honesty about verification:** this build has no GribStream account (creating
/// one is a real-world action with its own account/billing footprint that belongs to
/// whoever runs this app, not something to do on a user's behalf mid-build) --
/// request-building and response-parsing are both real and unit-tested against
/// fixtures matching the *documented* request/response shape, but neither has been
/// exercised against a live, authenticated response. The first real call is the
/// remaining verification step, gated on a token only the app's own user can supply.
public enum GTGForecastClient {
    public enum RequestError: Error {
        case couldNotEncodeBody
    }

    public enum ResponseError: Error {
        case malformedResponse
    }

    public static let defaultEndpoint = URL(string: "https://gribstream.com/api/v2/dafsgtg/timeseries")!

    public static func buildRequest(
        for plan: RouteForecastPlan, apiToken: String, endpoint: URL = GTGForecastClient.defaultEndpoint
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let isoFormatter = ISO8601DateFormatter()
        let coordinates: [[String: Any]] = plan.waypoints.enumerated().map { index, waypoint in
            [
                "lat": waypoint.coordinate.latitude, "lon": waypoint.coordinate.longitude,
                "name": waypointName(index),
            ]
        }
        let variables: [[String: Any]] = plan.levelsMetres.map { level in
            [
                "name": "CATEDR", "level": GTGLevel.levelString(forAltitudeMetres: level), "info": "",
                "alias": levelAlias(level),
            ]
        }
        let body: [String: Any] = [
            "timesList": plan.times.map { isoFormatter.string(from: $0) },
            "coordinates": coordinates,
            "variables": variables,
        ]

        guard JSONSerialization.isValidJSONObject(body),
              let bodyData = try? JSONSerialization.data(withJSONObject: body)
        else {
            throw RequestError.couldNotEncodeBody
        }
        request.httpBody = bodyData
        return request
    }

    /// Assumed response shape: a JSON array of rows, each carrying `lat`, `lon`,
    /// `forecasted_time` (ISO 8601), and one numeric column per requested variable
    /// under the exact `alias` this client requested it with -- aliasing every
    /// variable explicitly (rather than relying on GribStream's default column
    /// naming) is what makes this parse unambiguous without having seen a live
    /// response.
    public static func parse(_ data: Data, plan: RouteForecastPlan) throws -> [ForecastSample] {
        guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ResponseError.malformedResponse
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFraction = ISO8601DateFormatter()

        var samples: [ForecastSample] = []
        for row in rows {
            guard let lat = row["lat"] as? Double, let lon = row["lon"] as? Double,
                  let timeString = row["forecasted_time"] as? String,
                  let time = isoFormatter.date(from: timeString) ?? isoFormatterNoFraction.date(from: timeString)
            else { continue }

            let coordinate = Coordinate(latitude: lat, longitude: lon)
            for level in plan.levelsMetres {
                guard let value = row[levelAlias(level)] as? Double else { continue }
                samples.append(ForecastSample(
                    coordinate: coordinate, altitudeMetres: level, validTime: time, edrCubeRoot: value
                ))
            }
        }
        return samples
    }

    static func waypointName(_ index: Int) -> String { "wp\(index)" }
    static func levelAlias(_ metres: Double) -> String { "catedr_\(Int(metres.rounded()))" }
}
