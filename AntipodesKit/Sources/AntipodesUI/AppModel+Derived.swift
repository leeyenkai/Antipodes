import AntipodesCore
import AntipodesGlobe
import AntipodesPlaces
import AntipodesStats
import Foundation
import SwiftUI

public extension AppModel {
    // MARK: - Derived

    func yearInReview(_ year: Int) -> YearInReview {
        YearInReview.compute(
            year: year,
            log: log,
            rules: rules,
            gazetteer: gazetteer,
            factors: catalogue.emissionFactors,
            home: home
        )
    }

    /// The same, worked out off the main thread, for the review's own screen.
    func computeYearInReview(_ year: Int) async -> YearInReview {
        let (log, rules, gazetteer, factors, home) =
            (log, rules, gazetteer, catalogue.emissionFactors, home)
        return await Task.detached(priority: .userInitiated) {
            YearInReview.compute(
                year: year,
                log: log,
                rules: rules,
                gazetteer: gazetteer,
                factors: factors,
                home: home
            )
        }.value
    }

    /// Statistics for one trip, by the same engine and rules as the whole log.
    func statistics(forTrip tripID: UUID) -> TravelStatistics {
        StatisticsEngine.compute(for: log.restricted(toTrip: tripID), context: statisticsContext)
    }

    /// The same, worked out off the main thread.
    func computeStatistics(forTrip tripID: UUID) async -> TravelStatistics {
        let log = log.restricted(toTrip: tripID)
        let context = statisticsContext
        return await Task.detached(priority: .userInitiated) {
            StatisticsEngine.compute(for: log, context: context)
        }.value
    }

    // MARK: - What the Stats screen shows

    /// The statistics the Stats screen shows: the filtered slice's while a filter is set
    /// (§5.7), the whole log's otherwise.
    var shownStatistics: TravelStatistics {
        guard statsFilter.isActive else { return statistics }
        return filteredStatistics ?? emptyStatistics
    }

    /// The records behind those statistics, for the lists a number opens.
    var shownLog: TravelLog {
        statsFilter.isActive ? filteredLog : log
    }

    /// What the Stats filter keeps, in words — "2023 · Fjords · Rail · Work" — or `nil`
    /// while there is no filter.
    var statsFilterSummary: String? {
        guard statsFilter.isActive else { return nil }
        let parts = [
            statsFilter.year.map(String.init),
            statsFilter.tripID.flatMap { log.trip(id: $0) }.map { $0.displayName(model: self) },
            statsFilter.mode?.displayName,
            statsFilter.purpose?.displayName,
        ]
        return parts.compactMap(\.self).joined(separator: " · ")
    }

    /// The rules those statistics were counted by: a commute filter counts commutes.
    var shownRules: CountingRules {
        statsFilter.rules(from: rules)
    }

    /// Statistics of nothing, under the current rules — what a screen shows for the
    /// moment before its own numbers arrive.
    var emptyStatistics: TravelStatistics {
        StatisticsEngine.compute(for: .empty, context: StatisticsContext(rules: rules))
    }

    /// Each trip's records and dates, worked out once per change to the log.
    var tripIndex: TripIndex {
        if let cached = tripIndexCache, cached.revision == logRevision {
            return cached
        }
        let index = TripIndex(log: log, revision: logRevision)
        tripIndexCache = index
        return index
    }

    func visits(inTrip tripID: UUID) -> [Visit] {
        tripIndex.visits[tripID] ?? []
    }

    func journeys(inTrip tripID: UUID) -> [Journey] {
        tripIndex.journeys[tripID] ?? []
    }

    /// When a trip happened, from its earliest to its latest dated record, at the
    /// precision its records were dated to.
    func dates(ofTrip tripID: UUID) -> TripDates? {
        tripIndex.dates[tripID]
    }

    /// Trips newest first: by start date, then undated trips by when they were made.
    /// Each trip's dates are worked out once, not once per comparison.
    var tripsNewestFirst: [Trip] {
        log.trips
            .map { (trip: $0, start: dates(ofTrip: $0.id)?.start) }
            .sorted { first, second in
                switch (first.start, second.start) {
                case let (a?, b?): a > b
                case (nil, _?): false
                case (_?, nil): true
                case (nil, nil): (first.trip.createdAt ?? .distantPast)
                    > (second.trip.createdAt ?? .distantPast)
                }
            }
            .map(\.trip)
    }
}

/// When a trip happened, said no more precisely than its records were dated.
///
/// A trip whose visits are dated only "2019" happened in 2019; it did not run from
/// 1 January to 31 December, and it was not 365 days long.
/// Each trip's records and dates, from one pass over the log. A list of trips asks for
/// these once per row and per sort comparison; filtering the whole log each time made
/// the Trips screen slow down with the square of the log's size.
public struct TripIndex: Sendable {
    let revision: Int
    let visits: [UUID: [Visit]]
    let journeys: [UUID: [Journey]]
    let dates: [UUID: TripDates]

    init(log: TravelLog, revision: Int) {
        self.revision = revision
        var visits: [UUID: [Visit]] = [:]
        var journeys: [UUID: [Journey]] = [:]
        var dates: [UUID: [FlexibleDate]] = [:]
        for visit in log.visits {
            guard let trip = visit.tripID else { continue }
            visits[trip, default: []].append(visit)
            dates[trip, default: []].append(visit.date)
        }
        for journey in log.journeys {
            guard let trip = journey.tripID else { continue }
            journeys[trip, default: []].append(journey)
            dates[trip, default: []].append(contentsOf: journey.legs.map(\.date))
        }
        self.visits = visits
        self.journeys = journeys
        self.dates = dates.compactMapValues(TripDates.init)
    }
}

public struct TripDates: Hashable, Sendable {
    /// The earliest day it could have started, for ordering trips.
    public let start: CalendarDate
    public let end: CalendarDate
    /// Every dated record is dated to the day, so the span and its length are real.
    public let isExact: Bool

    init?(_ dates: [FlexibleDate]) {
        let known = dates.filter(\.isKnown)
        guard let start = known.compactMap(\.earliestDay).min(),
              let end = known.compactMap(\.latestDay).max()
        else { return nil }
        self.start = start
        self.end = end
        isExact = known.allSatisfy { $0.precision == .day || $0.precision == .range }
    }

    /// Days from first to last, counting both, where that is known.
    public var dayCount: Int? {
        isExact ? start.days(to: end) + 1 : nil
    }

    /// "12–20 Jun 2024", or "June 2019", "2019" or "2018–2019" when the records say no
    /// more than that.
    @MainActor
    public var text: String {
        if isExact {
            return Format.span(start, end)
        }
        if start.year == end.year, start.month == end.month {
            return "\(Format.monthName(start.month)) \(String(start.year))"
        }
        if start.year == end.year {
            return String(start.year)
        }
        return "\(String(start.year))–\(String(end.year))"
    }

    /// The text with its length where known: "12–20 Jun 2024 · 9 days".
    @MainActor
    public var textWithLength: String {
        dayCount.map { "\(text) · \(Format.ordinalCount($0, "day"))" } ?? text
    }
}
