import Foundation

/// A wall-clock time on a calendar day, with no time zone attached: "12 June 2024,
/// 08:35" as printed on a ticket.
///
/// A ticket's times are local to the station or airport, so a leg stores them as they
/// were printed and reads them in the place's own zone only when a duration is wanted
/// (§5.2). Storing an instant instead would make an overnight or cross-border leg shift
/// whenever the user looked at it from a different zone.
public struct LocalDateTime: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let date: CalendarDate
    public let hour: Int
    public let minute: Int

    public init?(date: CalendarDate, hour: Int, minute: Int) {
        guard (0 ... 23).contains(hour), (0 ... 59).contains(minute) else { return nil }
        self.date = date
        self.hour = hour
        self.minute = minute
    }

    /// Parses `YYYY-MM-DDTHH:MM`, the form the store and the export use.
    public init?(iso: String) {
        let halves = iso.split(separator: "T", omittingEmptySubsequences: false)
        guard halves.count == 2,
              let date = CalendarDate(iso: String(halves[0]))
        else { return nil }
        let clock = halves[1].split(separator: ":", omittingEmptySubsequences: false)
        guard clock.count == 2, clock[0].count == 2, clock[1].count == 2,
              let hour = Int(clock[0]), let minute = Int(clock[1])
        else { return nil }
        self.init(date: date, hour: hour, minute: minute)
    }

    public var iso: String {
        "\(date.iso)T\(String(format: "%02d:%02d", hour, minute))"
    }

    public var description: String {
        iso
    }

    public var clockText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Minutes since 1970-01-01T00:00 *on the wall clock*, ignoring zones.
    ///
    /// Only meaningful for comparing two times read in the same zone — a scheduled and
    /// an actual arrival at the same airport, which is exactly what a delay is.
    public var wallClockMinutes: Int {
        date.daysSinceEpoch * 1440 + hour * 60 + minute
    }

    /// The instant this wall-clock time names in a zone, honouring daylight saving.
    public func instant(in timeZone: TimeZone) -> Date? {
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)
    }

    public static func < (lhs: LocalDateTime, rhs: LocalDateTime) -> Bool {
        lhs.wallClockMinutes < rhs.wallClockMinutes
    }
}

/// The four times a ticket and a delay notice can give for a leg (§5.2). All optional:
/// times are entered by hand and most legs will have none (R-JLOG-8).
public struct LegTimes: Hashable, Sendable, Codable {
    public var scheduledDeparture: LocalDateTime?
    public var scheduledArrival: LocalDateTime?
    public var actualDeparture: LocalDateTime?
    public var actualArrival: LocalDateTime?

    public static let none = LegTimes()

    public init(
        scheduledDeparture: LocalDateTime? = nil,
        scheduledArrival: LocalDateTime? = nil,
        actualDeparture: LocalDateTime? = nil,
        actualArrival: LocalDateTime? = nil
    ) {
        self.scheduledDeparture = scheduledDeparture
        self.scheduledArrival = scheduledArrival
        self.actualDeparture = actualDeparture
        self.actualArrival = actualArrival
    }

    public var isEmpty: Bool {
        scheduledDeparture == nil && scheduledArrival == nil
            && actualDeparture == nil && actualArrival == nil
    }

    /// What actually happened where it is known, otherwise what was scheduled.
    public var bestDeparture: LocalDateTime? {
        actualDeparture ?? scheduledDeparture
    }

    public var bestArrival: LocalDateTime? {
        actualArrival ?? scheduledArrival
    }

    /// Delay = actual − scheduled arrival, in minutes; negative when early (§5.2).
    ///
    /// Both times are at the same station, so they share a zone and the wall clocks
    /// can be compared directly — no zone is needed, and none is guessed.
    public var arrivalDelayMinutes: Int? {
        guard let scheduledArrival, let actualArrival else { return nil }
        return actualArrival.wallClockMinutes - scheduledArrival.wallClockMinutes
    }

    public var departureDelayMinutes: Int? {
        guard let scheduledDeparture, let actualDeparture else { return nil }
        return actualDeparture.wallClockMinutes - scheduledDeparture.wallClockMinutes
    }
}

/// Where a leg's duration came from.
public enum DurationSource: String, Sendable, Codable {
    /// The user typed it.
    case userOverride
    /// Actual departure to actual arrival, each read in its own zone.
    case actualTimes
    /// Scheduled departure to scheduled arrival.
    case scheduledTimes
}

/// Why a duration could not be worked out.
public enum DurationUnavailableReason: String, Sendable, Codable {
    case noTimes
    case missingTimeZone
    case arrivesBeforeDeparture
}
