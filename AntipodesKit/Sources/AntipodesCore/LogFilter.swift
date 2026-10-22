import Foundation

/// A slice of the log for the stats screen: one year, one trip, one mode, one purpose,
/// or any mix of them (§5.7: "filterable by mode, year, trip and purpose").
///
/// A year or a trip keeps both visits and journeys. A mode or a purpose belongs to legs
/// alone, so either keeps only the legs that match and leaves visits out: "rail" is the
/// travelling done by train and the places reached by it, not every place ever visited.
public struct LogFilter: Hashable, Sendable {
    public var year: Int?
    public var tripID: UUID?
    public var mode: TravelMode?
    public var purpose: TripPurpose?

    public init(
        year: Int? = nil,
        tripID: UUID? = nil,
        mode: TravelMode? = nil,
        purpose: TripPurpose? = nil
    ) {
        self.year = year
        self.tripID = tripID
        self.mode = mode
        self.purpose = purpose
    }

    public static let none = LogFilter()

    public var isActive: Bool {
        self != .none
    }

    /// The filter with anything the log no longer holds taken off: a trip that has been
    /// deleted, or every part of it once the log is empty. A filter on a trip that is
    /// gone would otherwise show an empty slice under a blank name, with no way to see
    /// what it was.
    public func pruned(for log: TravelLog) -> LogFilter {
        guard !log.isEmpty else { return .none }
        var pruned = self
        if let tripID, log.trip(id: tripID) == nil {
            pruned.tripID = nil
        }
        return pruned
    }

    /// Whether a leg is in the slice.
    public func includes(_ leg: JourneyLeg, of journey: Journey) -> Bool {
        if let year, leg.date.year != year {
            return false
        }
        if let tripID, journey.tripID != tripID {
            return false
        }
        if let mode, leg.mode != mode {
            return false
        }
        if let purpose, leg.purpose != purpose {
            return false
        }
        return true
    }

    /// Whether a visit is in the slice. A mode or a purpose filter leaves visits out.
    public func includes(_ visit: Visit) -> Bool {
        guard mode == nil, purpose == nil else { return false }
        if let year, visit.date.year != year {
            return false
        }
        if let tripID, visit.tripID != tripID {
            return false
        }
        return true
    }

    /// The rules to count the slice by: asking for commutes means counting them, even
    /// where the user's own rule leaves them out of every other figure.
    public func rules(from rules: CountingRules) -> CountingRules {
        guard purpose == .commute else { return rules }
        var adjusted = rules
        adjusted.includeCommutes = true
        return adjusted
    }
}

public extension TravelLog {
    /// The part of the log a filter keeps. Trips stay, so trip names still resolve;
    /// journeys keep only their matching legs, and a journey left with none is dropped.
    func restricted(to filter: LogFilter) -> TravelLog {
        guard filter.isActive else { return self }
        return TravelLog(
            trips: trips,
            visits: visits.filter(filter.includes),
            journeys: journeys.compactMap { journey in
                let legs = journey.legs.filter { filter.includes($0, of: journey) }
                guard !legs.isEmpty else { return nil }
                var copy = journey
                copy.legs = legs
                return copy
            },
            wishlist: wishlist
        )
    }
}
