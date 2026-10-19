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

    /// Statistics for one trip, by the same engine and rules as the whole log.
    func statistics(forTrip tripID: UUID) -> TravelStatistics {
        StatisticsEngine.compute(for: log.restricted(toTrip: tripID), context: statisticsContext)
    }

    /// When a trip happened, from its earliest to its latest dated record.
    func dateSpan(ofTrip tripID: UUID) -> (start: CalendarDate, end: CalendarDate)? {
        let dates = log.visits(inTrip: tripID).map(\.date)
            + log.journeys(inTrip: tripID).flatMap { $0.legs.map(\.date) }
        guard let start = dates.compactMap(\.earliestDay).min(),
              let end = dates.compactMap(\.latestDay).max()
        else { return nil }
        return (start, end)
    }

    /// Trips newest first: by start date, then undated trips by when they were made.
    var tripsNewestFirst: [Trip] {
        log.trips.sorted { first, second in
            let a = dateSpan(ofTrip: first.id)?.start
            let b = dateSpan(ofTrip: second.id)?.start
            switch (a, b) {
            case let (a?, b?): return a > b
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return (first.createdAt ?? .distantPast) >
                (second.createdAt ?? .distantPast)
            }
        }
    }
}
