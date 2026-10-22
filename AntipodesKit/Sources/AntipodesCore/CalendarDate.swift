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

    /// Travel happens within these years. Bounding them keeps the day arithmetic below
    /// far from overflow whatever a damaged backup says.
    public static let supportedYears = -9999 ... 9999

    /// Fails on a date that does not exist, so a bad import is visible rather than
    /// silently rolled over into the next month.
    public init?(year: Int, month: Int, day: Int) {
        guard Self.supportedYears.contains(year),
              (1 ... 12).contains(month),
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

    /// Inverse of `daysSinceEpoch`, by Howard Hinnant's `civil_from_days`.
    public init?(daysSinceEpoch: Int) {
        let shifted = daysSinceEpoch + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthTerm = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthTerm + 2) / 5 + 1
        let month = monthTerm < 10 ? monthTerm + 3 : monthTerm - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.init(year: year, month: month, day: day)
    }

    /// The date `days` later, or earlier if negative, by exact day arithmetic.
    public func adding(days: Int) -> CalendarDate? {
        CalendarDate(daysSinceEpoch: daysSinceEpoch + days)
    }

    /// Today on the calendar of the given zone. The one place the app turns "now" into
    /// a calendar date; stats take the result as a parameter so they stay testable.
    public static func today(in timeZone: TimeZone = .current, now: Date = Date()) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
            ?? CalendarDate(year: 1970, month: 1, day: 1)!
    }

    /// Converts a `Date` the user picked, read on the calendar of the given zone.
    public init?(_ date: Date, in timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month,
              let day = parts.day else { return nil }
        self.init(year: year, month: month, day: day)
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

extension CalendarDate {
    private enum CodingKeys: String, CodingKey {
        case year, month, day
    }

    /// Goes through the checking initialiser, so a backup cannot carry 31 February or
    /// month 13 into the log — the record fails to read and the restore says so.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let date = try CalendarDate(
            year: container.decode(Int.self, forKey: .year),
            month: container.decode(Int.self, forKey: .month),
            day: container.decode(Int.self, forKey: .day)
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not a date on the calendar"
            ))
        }
        self = date
    }
}
