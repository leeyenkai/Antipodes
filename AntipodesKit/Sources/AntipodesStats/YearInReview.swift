import AntipodesCore
import Foundation

/// One year of travel, summed up for the Year in Review cards (R-SHARE-3).
///
/// Built entirely from the local log. A record belongs to a year when its date falls
/// inside it; undated records belong to no year and are counted in `undatedRecords`
/// rather than dropped in silence (R-DATE-2).
public struct YearInReview: Hashable, Sendable {
    public let year: Int
    public let countries: Set<String>
    public let countryNames: [String: String]
    /// Countries visited for the first time ever this year.
    public let newCountries: Set<String>
    public let cities: Int
    public let places: Int
    public let continents: Set<Continent>
    public let kilometres: Double
    public let flights: Int
    public let legs: Int
    public let daysAway: Int
    public let trips: Int
    public let longestLeg: JourneyLeg?
    public let busiestMonth: BusiestMonth?
    public let topThemes: [ThemeShare]
    public let personality: TravelPersonality?
    /// The personality from everything before this year, to show how it shifted.
    public let personalityBefore: TravelPersonality?
    public let carbonKg: Double?
    /// The year's northernmost and southernmost visits.
    public let northernmost: Visit?
    public let southernmost: Visit?
    /// Records with no date, which could not be placed in any year.
    public let undatedRecords: Int

    public var isEmpty: Bool {
        places == 0 && legs == 0
    }

    /// Every year the log has something dated in, newest first.
    public static func availableYears(in log: TravelLog) -> [Int] {
        Set(log.visits.compactMap(\.date.year) + log.allLegs.compactMap(\.date.year)).sorted(by: >)
    }

    public static func compute(
        year: Int,
        log: TravelLog,
        rules: CountingRules = .default,
        gazetteer: Gazetteer = .empty,
        factors: EmissionFactorTable = .empty,
        home: PlaceReference? = nil
    ) -> YearInReview {
        let thisYear = log.restricted(toYear: year)
        let before = TravelLog(
            trips: log.trips,
            visits: log.visits.filter { ($0.date.year ?? .max) < year },
            journeys: log.journeys.compactMap { journey in
                let legs = journey.legs.filter { ($0.date.year ?? .max) < year }
                guard !legs.isEmpty else { return nil }
                var copy = journey
                copy.legs = legs
                return copy
            }
        )

        let coverage = CoverageStatistics.compute(for: thisYear, rules: rules, gazetteer: gazetteer)
        let earlier = CoverageStatistics.compute(for: before, rules: rules, gazetteer: gazetteer)
        let distance = DistanceStatistics.compute(for: thisYear, rules: rules)
        let flights = FlightStatistics.compute(for: thisYear, rules: rules)
        let today = CalendarDate(year: year, month: 12, day: 31) ?? CalendarDate.today()
        let time = TimeStatistics.compute(for: thisYear, rules: rules, home: home, today: today)
        let themes = ThemeStatistics.compute(for: thisYear, rules: rules, gazetteer: gazetteer)
        let themesBefore = ThemeStatistics.compute(for: before, rules: rules, gazetteer: gazetteer)
        let extremes = ExtremePoints.compute(for: thisYear, rules: rules)
        let carbon = factors.isEmpty
            ? nil
            : CarbonStatistics.compute(for: thisYear, rules: rules, factors: factors).totalKg

        let tripIDs = Set(thisYear.visits.compactMap(\.tripID) + thisYear.journeys
            .compactMap(\.tripID))
        let undated = log.visits.count { !$0.date.isKnown } + log.allLegs.count { !$0.date.isKnown }

        return YearInReview(
            year: year,
            countries: coverage.countryCodes,
            countryNames: coverage.countryNames,
            newCountries: coverage.countryCodes.subtracting(earlier.countryCodes),
            cities: coverage.citiesVisited,
            places: Set(thisYear.visits.map(\.place.id)).count,
            continents: coverage.continents,
            kilometres: distance.totalKm,
            flights: flights.flightCount,
            legs: distance.legCount,
            daysAway: time.daysAwayByYear[year] ?? 0,
            trips: tripIDs.count,
            longestLeg: distance.longestLeg,
            busiestMonth: time.busiestMonth,
            topThemes: themes.topThemes,
            personality: themes.personality,
            personalityBefore: themesBefore.personality,
            carbonKg: carbon,
            northernmost: extremes.northernmost,
            southernmost: extremes.southernmost,
            undatedRecords: undated
        )
    }
}
