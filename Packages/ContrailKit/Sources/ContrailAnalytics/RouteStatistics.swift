import Foundation

/// ROADMAP Phase 4, verbatim: "Fly Denver to LA ten times and you have a real
/// distribution: how turbulent that route actually runs, seasonally and by time of
/// day." `distribution` pools every individual measured sample across every flight
/// on this route -- not one average per flight -- so it actually gets more precise
/// as more flights accumulate, the way a real distribution should.
public struct RouteStatistics: Sendable, Equatable, Identifiable {
    public var id: String { route }
    public let route: String
    public let flightCount: Int
    public let distribution: SampleDistribution?
    /// Mean EDR^(1/3) among samples departing in each time-of-day bucket, local to
    /// the flight's origin... except this build has no timezone dataset (that's a
    /// deferred 1.4 note that was never picked up), so the bucket is computed from
    /// the phone's own clock at the moment of each sample, in whatever timezone this
    /// device happened to be set to. Honest label, not a precise "local to origin."
    public let byTimeOfDay: [TimeOfDayBucket: Double]
    public let bySeason: [Season: Double]

    public init(
        route: String, flightCount: Int, distribution: SampleDistribution?,
        byTimeOfDay: [TimeOfDayBucket: Double], bySeason: [Season: Double]
    ) {
        self.route = route
        self.flightCount = flightCount
        self.distribution = distribution
        self.byTimeOfDay = byTimeOfDay
        self.bySeason = bySeason
    }
}

public enum TimeOfDayBucket: String, Sendable, CaseIterable, Equatable {
    case night = "Night"          // 00:00-05:59
    case morning = "Morning"      // 06:00-11:59
    case afternoon = "Afternoon"  // 12:00-17:59
    case evening = "Evening"      // 18:00-23:59

    public init(hour: Int) {
        switch hour {
        case 0..<6: self = .night
        case 6..<12: self = .morning
        case 12..<18: self = .afternoon
        default: self = .evening
        }
    }
}

public enum Season: String, Sendable, CaseIterable, Equatable {
    case winter = "Winter", spring = "Spring", summer = "Summer", fall = "Fall"

    public init(month: Int) {
        switch month {
        case 12, 1, 2: self = .winter
        case 3, 4, 5: self = .spring
        case 6, 7, 8: self = .summer
        default: self = .fall
        }
    }
}

public enum RouteStatisticsCompiler {
    public static func compile(from flights: [AnalyzedFlight], calendar: Calendar = .current) -> [RouteStatistics] {
        var byRoute: [String: (flightIDs: Set<String>, edrValues: [(Double, Date)])] = [:]

        for flight in flights {
            var entry = byRoute[flight.routeKey] ?? (flightIDs: [], edrValues: [])
            entry.flightIDs.insert(flight.manifest.flightID)
            for sample in flight.samples {
                if let edr = sample.turbulence.edrCubeRoot.value {
                    entry.edrValues.append((edr, sample.t))
                }
            }
            byRoute[flight.routeKey] = entry
        }

        return byRoute.map { route, entry in
            var byTimeOfDay: [TimeOfDayBucket: [Double]] = [:]
            var bySeason: [Season: [Double]] = [:]
            for (edr, date) in entry.edrValues {
                let hour = calendar.component(.hour, from: date)
                let month = calendar.component(.month, from: date)
                byTimeOfDay[TimeOfDayBucket(hour: hour), default: []].append(edr)
                bySeason[Season(month: month), default: []].append(edr)
            }

            return RouteStatistics(
                route: route,
                flightCount: entry.flightIDs.count,
                distribution: SampleDistribution.compute(entry.edrValues.map(\.0)),
                byTimeOfDay: byTimeOfDay.mapValues { average($0) },
                bySeason: bySeason.mapValues { average($0) }
            )
        }.sorted { $0.route < $1.route }
    }

    private static func average(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }
}
