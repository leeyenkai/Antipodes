import AntipodesCore
import Foundation

/// The days the replay scrubber can stop on, and what it cannot cover (§9).
///
/// The timeline is the list of days something actually happened rather than a
/// continuous range, so dragging it steps from trip to trip instead of crawling through
/// empty years. A log with three visits has three stops.
///
/// Undated records cannot be placed in time at all. They are counted here, not dropped,
/// so the screen can say "4 places have no date and are not in the replay" — the same
/// bargain every statistic in the app makes (R-DATE-2, R-CALC-5).
public struct GlobeTimeline: Sendable {
    public let stops: [CalendarDate]
    public let undatedVisitCount: Int
    public let undatedLegCount: Int

    public static let empty = GlobeTimeline(stops: [], undatedVisitCount: 0, undatedLegCount: 0)

    public var isEmpty: Bool {
        stops.isEmpty
    }

    public var earliest: CalendarDate? {
        stops.first
    }

    public var latest: CalendarDate? {
        stops.last
    }

    public var undatedCount: Int {
        undatedVisitCount + undatedLegCount
    }

    /// A sentence for under the scrubber, or `nil` when the replay covers everything.
    public var caveat: String? {
        guard undatedCount > 0 else { return nil }
        let thing = undatedCount == 1 ? "record has" : "records have"
        return "\(undatedCount) \(thing) no date and cannot be placed in the replay."
    }

    /// Builds the timeline from the log under the same year, trip and mode filters the
    /// globe is using, ignoring the replay position itself.
    public init(log: TravelLog, rules: CountingRules, filter: GlobeFilter = .none) {
        var days: Set<CalendarDate> = []
        var undatedVisits = 0
        var undatedLegs = 0

        for visit in log.visits {
            guard GlobeTimeline.passesFilter(filter, tripID: visit.tripID, date: visit.date)
            else { continue }
            if let day = visit.date.sortDay {
                days.insert(day)
            } else {
                undatedVisits += 1
            }
        }

        for journey in log.journeys {
            for leg in journey.legs {
                guard GlobeTimeline.passesFilter(filter, tripID: journey.tripID, date: leg.date),
                      filter.mode == nil || leg.mode == filter.mode,
                      rules.countsInStats(leg.purpose)
                else { continue }
                if let day = leg.date.sortDay {
                    days.insert(day)
                } else {
                    undatedLegs += 1
                }
            }
        }

        stops = days.sorted()
        undatedVisitCount = undatedVisits
        undatedLegCount = undatedLegs
    }

    init(stops: [CalendarDate], undatedVisitCount: Int, undatedLegCount: Int) {
        self.stops = stops
        self.undatedVisitCount = undatedVisitCount
        self.undatedLegCount = undatedLegCount
    }

    /// The stop at a position in `0...1`, for binding a slider.
    public func date(atProgress progress: Double) -> CalendarDate? {
        guard !stops.isEmpty else { return nil }
        let index = Int((Double(stops.count - 1) * min(1, max(0, progress))).rounded())
        return stops[min(stops.count - 1, max(0, index))]
    }

    public func index(ofProgress progress: Double) -> Int {
        guard stops.count > 1 else { return 0 }
        return Int((Double(stops.count - 1) * min(1, max(0, progress))).rounded())
    }

    public func date(atIndex index: Int) -> CalendarDate? {
        guard !stops.isEmpty, stops.indices.contains(index) else { return nil }
        return stops[index]
    }

    /// Year labels for the scrubber's ticks, with the index each one starts at.
    public var yearMarkers: [(year: Int, index: Int)] {
        var markers: [(year: Int, index: Int)] = []
        for (index, stop) in stops.enumerated() where markers.last?.year != stop.year {
            markers.append((stop.year, index))
        }
        return markers
    }

    private static func passesFilter(
        _ filter: GlobeFilter,
        tripID: UUID?,
        date: FlexibleDate
    ) -> Bool {
        if let year = filter.year, date.year != year {
            return false
        }
        if let wanted = filter.tripID, tripID != wanted {
            return false
        }
        return true
    }
}
