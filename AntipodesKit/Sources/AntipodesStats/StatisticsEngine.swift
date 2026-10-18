import AntipodesCore
import Foundation

/// Everything the stats screen shows, computed in one pass over the log.
///
/// The engine is a pure function of `(TravelLog, CountingRules)`. It holds no state,
/// touches no persistence and makes no network call, which is why it can be tested
/// exhaustively from the command line (decision D-2).
public struct TravelStatistics: Hashable, Sendable {
    public let coverage: CoverageStatistics
    public let distance: DistanceStatistics
    public let flights: FlightStatistics
    public let extremes: ExtremePoints
    public let rules: CountingRules

    /// Headline numbers for the top of the stats screen and the widgets.
    public var headlines: [Headline] {
        [
            Headline(
                id: "countries",
                title: "Countries",
                value: "\(coverage.countriesVisited)",
                detail: String(format: "%.1f%% of the world", coverage.worldFraction * 100),
                caveat: coverage.input.caveat
            ),
            Headline(
                id: "distance",
                title: "Distance",
                value: formattedDistance,
                detail: String(format: "%.2f× round the Earth", distance.timesRoundTheEarth),
                caveat: distance.input.caveat
            ),
            Headline(
                id: "continents",
                title: "Continents",
                value: "\(coverage.continentsVisited) of \(Continent.allSeven.count)",
                detail: coverage.hasVisitedAllSevenContinents ? "All seven" : nil,
                caveat: nil
            ),
            Headline(
                id: "flights",
                title: "Flights",
                value: "\(flights.flightCount)",
                detail: "\(flights.airportsVisited) airports",
                caveat: flights.input.caveat
            ),
        ]
    }

    public var formattedDistance: String {
        let value = rules.unitSystem.distance(fromKilometres: distance.totalKm)
        let unit = rules.unitSystem.distanceUnitAbbreviation
        return "\(Int(value.rounded())) \(unit)"
    }

    public struct Headline: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let value: String
        public let detail: String?
        public let caveat: String?
    }
}

public enum StatisticsEngine {
    /// Computes every statistic in scope for the current milestone.
    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        home: Coordinate? = nil
    ) -> TravelStatistics {
        TravelStatistics(
            coverage: CoverageStatistics.compute(for: log, rules: rules),
            distance: DistanceStatistics.compute(for: log, rules: rules),
            flights: FlightStatistics.compute(for: log, rules: rules),
            extremes: ExtremePoints.compute(for: log, rules: rules, home: home),
            rules: rules
        )
    }
}
