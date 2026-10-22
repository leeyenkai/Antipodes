import AntipodesCore
import Foundation

/// A place visited more than once.
public struct RepeatVisit: Hashable, Sendable {
    public let place: PlaceReference
    public let visitCount: Int
}

/// How long it has been since the user was last in a country.
public struct CountryGap: Hashable, Sendable {
    public let countryCode: String
    public let countryName: String
    public let lastVisited: CalendarDate
    public let daysSince: Int
}

/// A trip's span from its first dated day to its last.
public struct TripSpan: Hashable, Sendable {
    public let tripID: UUID
    public let start: CalendarDate
    public let end: CalendarDate

    public var days: Int {
        start.days(to: end) + 1
    }
}

/// Something that happened on today's date in an earlier year.
public struct OnThisDayEntry: Hashable, Sendable, Identifiable {
    public enum Record: Hashable, Sendable {
        case visit(Visit)
        case leg(JourneyLeg)
    }

    public let record: Record
    public let year: Int
    public let yearsAgo: Int

    public var id: UUID {
        switch record {
        case let .visit(visit): visit.id
        case let .leg(leg): leg.id
        }
    }
}

/// When the user travels: the time-and-patterns family (§7).
///
/// These count *visits*, not places (R-CALC-3): two trips to Rome are two data points
/// for seasonality. A stat that needs a date skips undated records and says so
/// (R-DATE-2); one that needs a day also skips month-only and year-only dates.
public struct TimeStatistics: Hashable, Sendable {
    /// Counted visits per year, by the year each is filed under (D-23).
    public let visitsByYear: [Int: Int]
    /// Countries visited for the first time, per year.
    public let newCountriesByYear: [Int: [String]]
    /// What the per-year counts could use: undated and uncounted visits are left out.
    public let yearInput: StatInputSummary
    /// Distinct days with a dated visit or leg away from home, per year.
    public let daysAwayByYear: [Int: Int]
    public let daysAwayInput: StatInputSummary

    /// Trips per year, by the year each trip started.
    public let tripsByYear: [Int: Int]
    public let tripSpans: [TripSpan]
    public let tripInput: StatInputSummary

    /// Visits per calendar month, January = 1, across every year (seasonality).
    public let visitsByMonth: [Int: Int]
    public let monthInput: StatInputSummary
    /// The single year-and-month with the most visits.
    public let busiestMonth: BusiestMonth?

    /// Places with more than one visit, most-visited first.
    public let repeatVisits: [RepeatVisit]

    /// Countries by how long it has been, longest first.
    public let countryGaps: [CountryGap]
    public let gapInput: StatInputSummary

    public let onThisDay: [OnThisDayEntry]
    public let today: CalendarDate

    public var averageTripDays: Double? {
        Summary.mean(tripSpans.map { Double($0.days) })
    }

    public var longestTrip: TripSpan? {
        tripSpans.max { ($0.days, $1.tripID.uuidString) < ($1.days, $0.tripID.uuidString) }
    }

    public var totalDaysAway: Int {
        daysAwayByYear.values.reduce(0, +)
    }

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        home: PlaceReference? = nil,
        today: CalendarDate
    ) -> TimeStatistics {
        let counted = log.visits.filter { rules.countsTowardsCoverage($0.visitType) }
        let uncounted = log.visits.count - counted.count

        // Visits per year, and the year each country was first seen.
        var visitsByYear: [Int: Int] = [:]
        var firstYearByCountry: [String: Int] = [:]
        var yearInput = StatInputSummary()
        for _ in 0 ..< uncounted {
            yearInput.exclude(.visitTypeNotCounted)
        }
        for visit in counted {
            guard let year = visit.date.year else {
                yearInput.exclude(.unknownDate)
                continue
            }
            yearInput.include()
            visitsByYear[year, default: 0] += 1
            if let code = visit.place.countryCode {
                firstYearByCountry[code] = min(firstYearByCountry[code] ?? year, year)
            }
        }
        var newCountriesByYear: [Int: [String]] = [:]
        for (code, year) in firstYearByCountry {
            newCountriesByYear[year, default: []].append(code)
        }
        for year in newCountriesByYear.keys {
            newCountriesByYear[year]?.sort()
        }

        let (daysAway, daysInput) = daysAway(log: log, rules: rules, home: home)
        let (tripsByYear, spans, tripInput) = trips(log: log)
        let (byMonth, monthInput, busiest) = seasonality(counted)
        let (gaps, gapInput) = countryGaps(counted, today: today)

        return TimeStatistics(
            visitsByYear: visitsByYear,
            newCountriesByYear: newCountriesByYear,
            yearInput: yearInput,
            daysAwayByYear: daysAway,
            daysAwayInput: daysInput,
            tripsByYear: tripsByYear,
            tripSpans: spans,
            tripInput: tripInput,
            visitsByMonth: byMonth,
            monthInput: monthInput,
            busiestMonth: busiest,
            repeatVisits: repeatVisits(counted),
            countryGaps: gaps,
            gapInput: gapInput,
            onThisDay: onThisDay(log: log, today: today),
            today: today
        )
    }

    // MARK: - Parts

    /// Distinct days away per year. A day is away if a counted visit outside the home
    /// city covers it, or a leg was travelled on it. Each day counts once however much
    /// happened on it. A layover still puts its day in, through the flight's leg.
    static func daysAway(
        log: TravelLog,
        rules: CountingRules,
        home: PlaceReference?
    ) -> ([Int: Int], StatInputSummary) {
        var input = StatInputSummary()
        var days: Set<CalendarDate> = []

        /// Adds the record's days, or says why it has none to add.
        func addDays(of date: FlexibleDate) -> ExclusionReason? {
            switch date {
            case let .day(day):
                days.insert(day)
                return nil
            case let .range(start, end):
                // A two-year sabbatical is still a span of days. A range past ten years
                // is a mistyped year, and is left out and counted as such rather than
                // trimmed to a decade nobody spent away.
                let count = start.days(to: end)
                guard count <= maximumRangeDays else { return .dateRangeTooLong }
                var day = start
                for _ in 0 ... max(0, count) {
                    days.insert(day)
                    guard let following = day.adding(days: 1) else { break }
                    day = following
                }
                return nil
            case .month, .year, .unknown:
                return .datePrecisionTooLow
            }
        }

        for visit in log.visits {
            guard rules.countsTowardsCoverage(visit.visitType) else {
                input.exclude(.visitTypeNotCounted)
                continue
            }
            if let home, visit.place.covers(home) || home.covers(visit.place) {
                input.exclude(.atHome)
                continue
            }
            guard visit.date.isKnown else {
                input.exclude(.unknownDate)
                continue
            }
            if let reason = addDays(of: visit.date) {
                input.exclude(reason)
            } else {
                input.include()
            }
        }
        for leg in log.allLegs where rules.countsInStats(leg.purpose) {
            guard leg.date.isKnown else {
                input.exclude(.unknownDate)
                continue
            }
            if let reason = addDays(of: leg.date) {
                input.exclude(reason)
            } else {
                input.include()
            }
        }

        var byYear: [Int: Int] = [:]
        for day in days {
            byYear[day.year, default: 0] += 1
        }
        return (byYear, input)
    }

    /// The longest range "days away" will spread over: ten years and a leap day or two.
    static let maximumRangeDays = 3660

    /// Trips per start year, and each trip's span where its first and last days are
    /// known to the day.
    static func trips(log: TravelLog) -> ([Int: Int], [TripSpan], StatInputSummary) {
        var byYear: [Int: Int] = [:]
        var spans: [TripSpan] = []
        var input = StatInputSummary()

        for trip in log.trips {
            let dates = log.visits(inTrip: trip.id).map(\.date)
                + log.journeys(inTrip: trip.id).flatMap { $0.legs.map(\.date) }
            let known = dates.filter(\.isKnown)
            guard let start = known.compactMap(\.earliestDay).min() else {
                input.exclude(dates.isEmpty ? .notInATrip : .unknownDate)
                continue
            }
            input.include()
            byYear[start.year, default: 0] += 1

            // A span needs exact ends. A trip dated only "June 2024" has a start month,
            // not a length, and inventing one from the month's first and last day
            // would report a thirty-day trip that may have been a weekend.
            let exact = known.filter { $0.precision == .day || $0.precision == .range }
            if let first = exact.compactMap(\.earliestDay).min(),
               let last = exact.compactMap(\.latestDay).max() {
                spans.append(TripSpan(tripID: trip.id, start: first, end: last))
            }
        }
        return (byYear, spans.sorted { $0.start < $1.start }, input)
    }

    static func seasonality(
        _ visits: [Visit]
    ) -> ([Int: Int], StatInputSummary, BusiestMonth?) {
        var byMonth: [Int: Int] = [:]
        var byYearMonth: [YearMonth: Int] = [:]
        var input = StatInputSummary()
        for visit in visits {
            // A range is filed under the month it began, as it is under the year it
            // began (D-23); only a bare year has no month at all.
            guard let month = visit.date.startMonth, let year = visit.date.year else {
                input.exclude(visit.date.isKnown ? .datePrecisionTooLow : .unknownDate)
                continue
            }
            input.include()
            byMonth[month, default: 0] += 1
            byYearMonth[YearMonth(year: year, month: month), default: 0] += 1
        }
        let busiest = byYearMonth
            .max { ($0.value, $1.key) < ($1.value, $0.key) }
            .map { BusiestMonth(year: $0.key.year, month: $0.key.month, visits: $0.value) }
        return (byMonth, input, busiest)
    }

    static func repeatVisits(_ visits: [Visit]) -> [RepeatVisit] {
        var counts: [PlaceID: (PlaceReference, Int)] = [:]
        for visit in visits {
            let existing = counts[visit.place.id]
            counts[visit.place.id] = (visit.place, (existing?.1 ?? 0) + 1)
        }
        return counts.values
            .filter { $0.1 > 1 }
            .map { RepeatVisit(place: $0.0, visitCount: $0.1) }
            .sorted { ($0.visitCount, $1.place.name) > ($1.visitCount, $0.place.name) }
    }

    static func countryGaps(
        _ visits: [Visit],
        today: CalendarDate
    ) -> ([CountryGap], StatInputSummary) {
        var last: [String: (CalendarDate, String)] = [:]
        var input = StatInputSummary()
        for visit in visits {
            guard let code = visit.place.countryCode else {
                input.exclude(.missingCountry)
                continue
            }
            guard let day = visit.date.latestDay else {
                input.exclude(.unknownDate)
                continue
            }
            input.include()
            if last[code].map({ day > $0.0 }) ?? true {
                last[code] = (day, visit.place.countryName ?? code)
            }
        }
        let gaps = last
            .map { code, entry in
                CountryGap(
                    countryCode: code,
                    countryName: entry.1,
                    lastVisited: entry.0,
                    daysSince: max(0, entry.0.days(to: today))
                )
            }
            .sorted { ($0.daysSince, $1.countryName) > ($1.daysSince, $0.countryName) }
        return (gaps, input)
    }

    /// Visits and legs on today's month and day in an earlier year. A range counts when
    /// it spans today's date; a month or a year does not, because "on this day" is a
    /// claim about the day.
    public static func onThisDay(log: TravelLog, today: CalendarDate) -> [OnThisDayEntry] {
        func matchingYear(_ date: FlexibleDate) -> Int? {
            switch date {
            case let .day(day):
                return day.month == today.month && day.day == today.day && day.year < today.year
                    ? day.year : nil
            case let .range(start, end):
                let lastYear = min(end.year, today.year - 1)
                guard start.year <= lastYear else { return nil }
                for year in start.year ... lastYear {
                    guard let candidate = CalendarDate(
                        year: year,
                        month: today.month,
                        day: today.day
                    )
                    else { continue }
                    if candidate >= start, candidate <= end {
                        return year
                    }
                }
                return nil
            case .month, .year, .unknown:
                return nil
            }
        }

        var entries: [OnThisDayEntry] = []
        for visit in log.visits {
            if let year = matchingYear(visit.date) {
                entries.append(OnThisDayEntry(
                    record: .visit(visit),
                    year: year,
                    yearsAgo: today.year - year
                ))
            }
        }
        for leg in log.allLegs {
            if let year = matchingYear(leg.date) {
                entries.append(OnThisDayEntry(
                    record: .leg(leg),
                    year: year,
                    yearsAgo: today.year - year
                ))
            }
        }
        return entries.sorted { ($0.year, $0.id.uuidString) > ($1.year, $1.id.uuidString) }
    }
}

struct YearMonth: Hashable, Comparable {
    let year: Int
    let month: Int

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// The calendar month with the most visits in it.
public struct BusiestMonth: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let visits: Int

    public init(year: Int, month: Int, visits: Int) {
        self.year = year
        self.month = month
        self.visits = visits
    }
}
