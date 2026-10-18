import Foundation

/// A date on the calendar, with no time and no time zone.
///
/// A travel date is "12 June 2024", not an instant. Storing `Date` would make a visit
/// shift day depending on where the user is standing when they look at it, so the app
/// uses this throughout and converts only at the edges.
public struct CalendarDate: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Fails on a date that does not exist, so a bad import is visible rather than
    /// silently rolled over into the next month.
    public init?(year: Int, month: Int, day: Int) {
        guard (1 ... 12).contains(month),
              day >= 1,
              day <= CalendarDate.daysIn(month: month, year: year)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`. Used by the CSV and JSON importers.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        case 2: isLeapYear(year) ? 29 : 28
        default: 0
        }
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public var iso: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String {
        iso
    }

    /// Days since 1 January 1970, by Howard Hinnant's `days_from_civil`.
    ///
    /// Integer arithmetic, no `Calendar`, no time zone, so date differences are exact
    /// and identical on every device.
    public var daysSinceEpoch: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthTerm = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * monthTerm + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Whole days from this date to `other`, negative if `other` is earlier.
    public func days(to other: CalendarDate) -> Int {
        other.daysSinceEpoch - daysSinceEpoch
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Converts for display only. The app never stores the result.
    public func date(in timeZone: TimeZone = .gmt) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)
    }
}
