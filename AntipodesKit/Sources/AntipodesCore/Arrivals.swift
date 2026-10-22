import Foundation

/// Where journeys arrived, as the visits they imply (D-32).
///
/// Countries and cities come from visits (R-CALC-1), so a flight to Tokyo on its own
/// adds no country. The app offers to log the arrival as a visit instead — on saving a
/// journey, and for every journey an import brings in — and these are the rules for
/// which arrivals are worth offering. They are rules rather than guesses: the arrival is
/// the last stop of a run of connections, never home, never a visit already logged.
public enum Arrivals {
    /// Whether a leg by this mode takes the traveller somewhere new. A city transit ride
    /// or a cable car moves them about a place they are already in.
    public static func takesYouSomewhere(_ mode: TravelMode) -> Bool {
        switch mode {
        case .flight, .rail, .coach, .ferry, .roadTrip, .humanPowered: true
        case .cityTransit, .cableAndMountain: false
        }
    }

    /// The day a leg arrived: the day of its arrival time where one is known — an
    /// overnight flight lands the day after it left — and otherwise the leg's own date.
    public static func arrivalDate(of leg: JourneyLeg) -> FlexibleDate {
        leg.times.bestArrival.map { .day($0.date) } ?? leg.date
    }

    /// The legs that end somewhere: the last of each run of connections. A leg is a
    /// connection when the next one leaves from where it arrived by the following day,
    /// so OSL → HEL → HND arrives in Tokyo, not Helsinki, while a return flight a week
    /// later is an arrival of its own.
    public static func finalLegs(of legs: [JourneyLeg]) -> [JourneyLeg] {
        let ordered = legs.enumerated().sorted { first, second in
            let a = first.element, b = second.element
            let dayA = a.date.earliestDay, dayB = b.date.earliestDay
            if dayA != dayB {
                // Undated legs last, in the order given.
                guard let dayA else { return false }
                guard let dayB else { return true }
                return dayA < dayB
            }
            let timeA = a.times.bestDeparture, timeB = b.times.bestDeparture
            if let timeA, let timeB, timeA != timeB {
                return timeA < timeB
            }
            return first.offset < second.offset
        }.map(\.element)

        return ordered.enumerated().compactMap { index, leg in
            guard takesYouSomewhere(leg.mode) else { return nil }
            if index + 1 < ordered.count, connects(leg, to: ordered[index + 1]) {
                return nil
            }
            return leg
        }
    }

    /// Whether `next` leaves from where `leg` arrived, the same day or the day after.
    static func connects(_ leg: JourneyLeg, to next: JourneyLeg) -> Bool {
        guard next.origin.id == leg.destination.id,
              let arrived = arrivalDate(of: leg).latestDay,
              let leaves = next.date.earliestDay else { return false }
        return (0 ... 1).contains(arrived.days(to: leaves))
    }

    /// Whether arriving at `place` on `date` should be logged as a visit: not at home or
    /// somewhere home stands for, and not where a visit is already logged on those days.
    /// An undated arrival is logged only where there is no visit to the place at all.
    public static func shouldLog(
        _ place: PlaceReference,
        on date: FlexibleDate,
        home: PlaceReference?,
        existing: [Visit]
    ) -> Bool {
        if let home, home.covers(place) || place.covers(home) {
            return false
        }
        let there = existing.filter { $0.place.id == place.id }
        guard !there.isEmpty else { return true }
        guard let start = date.earliestDay, let end = date.latestDay else { return false }
        return !there.contains { visit in
            guard let from = visit.date.earliestDay, let to = visit.date.latestDay else {
                return false
            }
            return from <= end && start <= to
        }
    }

    /// The arrivals to log, in order, from places already resolved (an airport to the
    /// city it serves): each passes `shouldLog` against the log and the arrivals before
    /// it, so two flights into Tokyo on one day make one visit.
    public static func visits(
        arrivingAt arrivals: [(place: PlaceReference, date: FlexibleDate)],
        home: PlaceReference?,
        existing: [Visit]
    ) -> [(place: PlaceReference, date: FlexibleDate)] {
        var known = existing
        var planned: [(place: PlaceReference, date: FlexibleDate)] = []
        for arrival in arrivals
            where shouldLog(arrival.place, on: arrival.date, home: home, existing: known) {
            planned.append(arrival)
            known.append(Visit(place: arrival.place, date: arrival.date))
        }
        return planned
    }
}
