import Foundation
import ContrailCore
import ContrailLog

/// Computes `GeneratedProfileStats` from a pilot's own logged flights. A pure
/// function over already-decoded manifests/records, deliberately -- it knows nothing
/// about `Documents/Flights/` or any other on-disk layout; the app layer is
/// responsible for loading each flight via `FlightLogStore` and handing the result
/// here.
public enum GeneratedProfileCompiler {
    public struct FlightData: Sendable {
        public let manifest: FlightManifest
        public let records: [LogRecord]

        public init(manifest: FlightManifest, records: [LogRecord]) {
            self.manifest = manifest
            self.records = records
        }
    }

    public static func compile(from flights: [FlightData]) -> GeneratedProfileStats {
        guard !flights.isEmpty else { return .empty }

        var totalHours = 0.0
        var totalDistanceMetres = 0.0
        var routeAccumulator: [String: (count: Int, edrSum: Double, edrCount: Int)] = [:]
        var flightAverageEDRs: [Double] = []
        var residuals: [Double] = []
        var scheduleDeltas: [Double] = []
        var flightsWithSamples = 0

        for flight in flights {
            let samples = flight.records.filter { $0.kind == .sample }
            guard !samples.isEmpty else { continue }
            flightsWithSamples += 1

            let airborne = samples.filter { $0.phase.value != .taxi }
            if let first = airborne.first?.t, let last = airborne.last?.t, last > first {
                totalHours += last.timeIntervalSince(first) / 3600
            }

            if let flownDistance = samples.last?.route.alongTrackFlown.value {
                totalDistanceMetres += flownDistance
            }

            let edrValues = samples.compactMap { $0.turbulence.edrCubeRoot.value }
            let flightAverageEDR = edrValues.isEmpty ? nil : edrValues.reduce(0, +) / Double(edrValues.count)
            if let flightAverageEDR {
                flightAverageEDRs.append(flightAverageEDR)
            }

            let routeKey = "\(flight.manifest.flight.origin.icao)-\(flight.manifest.flight.destination.icao)"
            var entry = routeAccumulator[routeKey] ?? (count: 0, edrSum: 0, edrCount: 0)
            entry.count += 1
            if let flightAverageEDR {
                entry.edrSum += flightAverageEDR
                entry.edrCount += 1
            }
            routeAccumulator[routeKey] = entry

            for sample in samples {
                if let measured = sample.turbulence.edrCubeRoot.value,
                   let forecast = sample.turbulence.forecastEdrCubeRoot.value {
                    residuals.append(measured - forecast)
                }
            }

            if let finalScheduleDelta = samples.last?.route.eta.value?.scheduleDelta {
                scheduleDeltas.append(finalScheduleDelta)
            }
        }

        guard flightsWithSamples > 0 else { return .empty }

        let routes = routeAccumulator.map { key, value in
            GeneratedProfileStats.RouteFrequency(
                route: key, count: value.count,
                averageEDRCubeRoot: value.edrCount > 0 ? value.edrSum / Double(value.edrCount) : nil
            )
        }.sorted { $0.route < $1.route }

        let routesWithData = routes.filter { $0.averageEDRCubeRoot != nil }
        let roughest = routesWithData.max { $0.averageEDRCubeRoot! < $1.averageEDRCubeRoot! }
        let smoothest = routesWithData.min { $0.averageEDRCubeRoot! < $1.averageEDRCubeRoot! }

        return GeneratedProfileStats(
            flightsLogged: flights.count,
            hoursAtAltitude: totalHours,
            totalDistanceNauticalMiles: totalDistanceMetres / 1852.0,
            routes: routes,
            roughestRoute: roughest,
            smoothestRoute: smoothest,
            personalAverageEDRCubeRoot: average(flightAverageEDRs),
            turbulenceLuckDelta: average(residuals),
            averageScheduleDeltaSeconds: average(scheduleDeltas)
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
