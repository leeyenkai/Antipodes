import AntipodesCore
import Foundation

/// A flight read from a file, matched to the bundled airports and ready to review.
public struct FlightImportCandidate: Hashable, Sendable, Identifiable {
    public enum Status: Hashable, Sendable {
        case ready
        /// One or both airports could not be matched; the user can pick them by hand.
        case needsAirport
        /// The same flight is already in the log, or earlier in the same file.
        case duplicate
        /// The file says the flight was cancelled, so it was never flown.
        case cancelled
    }

    public var id: Int {
        row.line
    }

    public var row: FlightImportRow
    public var origin: PlaceReference?
    public var destination: PlaceReference?
    public var include: Bool

    public var status: Status {
        if row.isCancelled {
            return .cancelled
        }
        if origin == nil || destination == nil {
            return .needsAirport
        }
        return isDuplicate ? .duplicate : .ready
    }

    public var isDuplicate: Bool

    public init(
        row: FlightImportRow,
        origin: PlaceReference?,
        destination: PlaceReference?,
        isDuplicate: Bool
    ) {
        self.row = row
        self.origin = origin
        self.destination = destination
        self.isDuplicate = isDuplicate
        include = origin != nil && destination != nil && !isDuplicate && !row.isCancelled
    }

    /// The leg this candidate becomes, once both airports are known.
    ///
    /// Times the file stamped with a zone are first moved to each airport's own clock,
    /// which is how a leg stores them (§5.2).
    ///
    /// Exports that give only a clock time for arrival leave an overnight flight landing
    /// "before" it took off. Once both airports' zones are known that is detectable, and
    /// the only reading that makes sense is a later day. Westbound across the date line
    /// it can be two days — Los Angeles at 22:00 to Sydney at 06:00 — and no flight is
    /// longer than that, so the arrival moves forward at most twice.
    ///
    /// A flight time stated in the file stands in for the duration when the file has no
    /// times to work one out from.
    public var leg: JourneyLeg? {
        guard var leg = rawLeg else { return nil }
        for _ in 0 ..< 2 {
            guard case let .failure(failure) = leg.duration,
                  failure.reason == .arrivesBeforeDeparture else { break }
            leg.times.scheduledArrival = leg.times.scheduledArrival?.nextDay
            leg.times.actualArrival = leg.times.actualArrival?.nextDay
        }
        if leg.durationMinutes == nil, let stated = row.durationMinutes {
            leg.durationMinutesOverride = stated
        }
        return leg
    }

    private var rawLeg: JourneyLeg? {
        guard let origin, let destination else { return nil }
        func local(
            _ time: LocalDateTime?,
            _ offset: Int?,
            at place: PlaceReference
        ) -> LocalDateTime? {
            time.map { StampedTime(time: $0, offsetMinutes: offset).local(in: place.timeZone) }
        }
        let offsets = row.timeOffsets
        let times = LegTimes(
            scheduledDeparture: local(
                row.times.scheduledDeparture,
                offsets.scheduledDeparture,
                at: origin
            ),
            scheduledArrival: local(
                row.times.scheduledArrival,
                offsets.scheduledArrival,
                at: destination
            ),
            actualDeparture: local(row.times.actualDeparture, offsets.actualDeparture, at: origin),
            actualArrival: local(row.times.actualArrival, offsets.actualArrival, at: destination)
        )
        return JourneyLeg(
            mode: .flight,
            origin: origin,
            destination: destination,
            date: row.date,
            purpose: row.purpose ?? .leisure,
            times: times,
            operatorName: row.airline,
            serviceNumber: row.flightNumber,
            vehicle: row.aircraft,
            registration: row.registration,
            travelClass: row.travelClass,
            seat: row.seat,
            notes: row.notes
        )
    }
}

public extension FlightLogImport {
    /// Matches every row's airports by code, and flags flights already in the log.
    ///
    /// `airport` looks a code up in the bundled database; it is a parameter so this
    /// stays testable without one.
    static func match(
        _ rows: [FlightImportRow],
        existing: [JourneyLeg],
        airport: @Sendable (String) async -> PlaceReference?
    ) async -> [FlightImportCandidate] {
        var cache: [String: PlaceReference?] = [:]
        func lookUp(_ code: String?) async -> PlaceReference? {
            guard let code else { return nil }
            if let cached = cache[code] {
                return cached
            }
            let found = await airport(code)
            cache[code] = found
            return found
        }

        var known = FlightIndex(existing.filter { $0.mode == .flight })
        var candidates: [FlightImportCandidate] = []
        for row in rows {
            let origin = await lookUp(row.originCode)
            let destination = await lookUp(row.destinationCode)
            var duplicate = false
            if let origin, let destination, !row.isCancelled {
                let probe = JourneyLeg(
                    mode: .flight,
                    origin: origin,
                    destination: destination,
                    date: row.date,
                    serviceNumber: row.flightNumber
                )
                duplicate = known.contains(probe)
                // A file can list the same flight twice; the second is a duplicate of
                // the first just as much as of one already logged.
                known.insert(probe)
            }
            candidates.append(
                FlightImportCandidate(
                    row: row,
                    origin: origin,
                    destination: destination,
                    isDuplicate: duplicate
                )
            )
        }
        return candidates
    }

    /// Which flights are already known, for spotting a duplicate.
    ///
    /// Two flights are the same when they share the day and both ends, and their flight
    /// numbers agree — or either side has none. A flight logged by hand without its
    /// number is the same trip as the SK903 an import finds on that day and route;
    /// treating them as two would put the journey in the log twice.
    internal struct FlightIndex {
        struct Route: Hashable {
            let date: FlexibleDate
            let origin: PlaceID
            let destination: PlaceID
        }

        /// The flight numbers known for each day and route; `nil` is a flight logged
        /// without one.
        private var numbers: [Route: Set<String?>] = [:]

        init(_ legs: [JourneyLeg]) {
            for leg in legs {
                insert(leg)
            }
        }

        mutating func insert(_ leg: JourneyLeg) {
            numbers[Self.route(leg), default: []].insert(Self.number(leg))
        }

        func contains(_ leg: JourneyLeg) -> Bool {
            guard let known = numbers[Self.route(leg)] else { return false }
            guard let number = Self.number(leg) else { return true }
            return known.contains(number) || known.contains(nil)
        }

        static func route(_ leg: JourneyLeg) -> Route {
            Route(date: leg.date, origin: leg.origin.id, destination: leg.destination.id)
        }

        static func number(_ leg: JourneyLeg) -> String? {
            let cleaned = leg.serviceNumber?.uppercased().filter { !$0.isWhitespace }
            return cleaned?.isEmpty == false ? cleaned : nil
        }
    }
}
