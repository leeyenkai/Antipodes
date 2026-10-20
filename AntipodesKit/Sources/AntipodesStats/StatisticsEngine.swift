import AntipodesCore
import Foundation

/// What the engine needs besides the log: the rules, and the facts it may not look up
/// itself (decision D-2). Everything has an empty default, so a test passes only what it
/// is testing.
public struct StatisticsContext: Sendable {
    public var rules: CountingRules
    public var gazetteer: Gazetteer
    public var home: PlaceReference?
    /// "Today", passed in so time-based stats are reproducible in a test.
    public var today: CalendarDate
    public var emissionFactors: EmissionFactorTable
    public var collections: [CollectionDefinition]
    public var achievements: [AchievementDefinition]
    public var routes: [RouteInfo]

    public init(
        rules: CountingRules = .default,
        gazetteer: Gazetteer = .empty,
        home: PlaceReference? = nil,
        today: CalendarDate = .today(),
        emissionFactors: EmissionFactorTable = .empty,
        collections: [CollectionDefinition] = [],
        achievements: [AchievementDefinition] = [],
        routes: [RouteInfo] = []
    ) {
        self.rules = rules
        self.gazetteer = gazetteer
        self.home = home
        self.today = today
        self.emissionFactors = emissionFactors
        self.collections = collections
        self.achievements = achievements
        self.routes = routes
    }
}

/// Everything the stats screen shows, computed in one pass over the log.
///
/// The engine is a pure function of the log and its context. It holds no state, touches
/// no persistence and makes no network call, which is why it can be tested exhaustively
/// from the command line (decision D-2).
public struct TravelStatistics: Hashable, Sendable {
    public let coverage: CoverageStatistics
    public let distance: DistanceStatistics
    public let flights: FlightStatistics
    public let extremes: ExtremePoints
    public let attributes: PlaceAttributeStatistics
    public let time: TimeStatistics
    public let themes: ThemeStatistics
    public let journeys: JourneyStatistics
    public let rail: RailStatistics
    public let punctuality: PunctualityStatistics
    public let carbon: CarbonStatistics
    public let collections: [CollectionProgress]
    public let wishlist: [WishlistStatus]
    public let achievements: [AchievementStatus]
    public let rules: CountingRules

    public var personality: TravelPersonality? {
        themes.personality
    }

    public var earnedAchievements: [AchievementStatus] {
        achievements.filter(\.isEarned)
    }

    /// Headline numbers for the top of the stats screen and the widgets.
    public var headlines: [Headline] {
        [
            Headline(
                id: "countries",
                title: "Countries",
                value: "\(coverage.listedCountriesVisited)",
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
        return "\(Int(value.rounded()).formatted()) \(unit)"
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
    /// Computes every statistic for a log.
    public static func compute(for log: TravelLog, context: StatisticsContext) -> TravelStatistics {
        let rules = context.rules
        let gazetteer = context.gazetteer
        let collections = CollectionProgress.compute(
            collections: context.collections,
            log: log,
            rules: rules,
            routes: context.routes
        )
        return TravelStatistics(
            coverage: CoverageStatistics.compute(for: log, rules: rules, gazetteer: gazetteer),
            distance: DistanceStatistics.compute(for: log, rules: rules),
            flights: FlightStatistics.compute(for: log, rules: rules),
            extremes: ExtremePoints.compute(
                for: log,
                rules: rules,
                home: context.home?.coordinate,
                gazetteer: gazetteer
            ),
            attributes: PlaceAttributeStatistics.compute(
                for: log,
                rules: rules,
                gazetteer: gazetteer,
                referenceYear: context.today.year
            ),
            time: TimeStatistics.compute(
                for: log,
                rules: rules,
                home: context.home,
                today: context.today
            ),
            themes: ThemeStatistics.compute(for: log, rules: rules, gazetteer: gazetteer),
            journeys: JourneyStatistics.compute(for: log, rules: rules),
            rail: RailStatistics.compute(for: log, rules: rules, routes: context.routes),
            punctuality: PunctualityStatistics.compute(for: log, rules: rules),
            carbon: CarbonStatistics.compute(
                for: log,
                rules: rules,
                factors: context.emissionFactors
            ),
            collections: collections,
            wishlist: WishlistStatus.compute(log: log, rules: rules, routes: context.routes),
            achievements: AchievementEngine.evaluate(
                context.achievements,
                log: log,
                rules: rules,
                gazetteer: gazetteer,
                collections: collections
            ),
            rules: rules
        )
    }

    /// The M1 entry point, kept for callers that only have rules and a home.
    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        home: Coordinate? = nil
    ) -> TravelStatistics {
        compute(
            for: log,
            context: StatisticsContext(
                rules: rules,
                home: home.map {
                    PlaceReference(id: .custom(UUID()), kind: .custom, name: "Home", coordinate: $0)
                }
            )
        )
    }
}
