import Foundation

/// When something happened, at whatever precision the user actually remembers.
///
/// Users logging past travel often know the year but not the month, or the month but
/// not the day. Forcing an exact date would mean inventing data, so unknown is a
/// first-class case here and every stat has to decide what to do with it (R-DATE-1,
/// R-DATE-2).
public enum FlexibleDate: Hashable, Sendable, Codable {
    /// A single day.
    case day(CalendarDate)
    /// A span of days, inclusive at both ends. `start <= end` is enforced on creation.
    case range(start: CalendarDate, end: CalendarDate)
    /// A month, with no day known.
    case month(year: Int, month: Int)
    /// A year, with no month known.
    case year(Int)
    /// Nothing known.
    case unknown

    /// Builds a range, normalising reversed input rather than rejecting it — a user
    /// dragging a date picker backwards means a range, not an error.
    public static func span(_ first: CalendarDate, _ second: CalendarDate) -> FlexibleDate {
        first <= second
            ? .range(start: first, end: second)
            : .range(start: second, end: first)
    }

    public static func month(_ year: Int, _ month: Int) -> FlexibleDate? {
        guard (1 ... 12).contains(month) else { return nil }
        return .month(year: year, month: month)
    }

    // MARK: - Precision

    public enum Precision: Int, Sendable, Codable, Comparable, CaseIterable {
        case unknown = 0
        case year = 1
        case month = 2
        case range = 3
        case day = 4

        public static func < (lhs: Precision, rhs: Precision) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public var precision: Precision {
        switch self {
        case .day: .day
        case .range: .range
        case .month: .month
        case .year: .year
        case .unknown: .unknown
        }
    }

    public var isKnown: Bool {
        precision != .unknown
    }

    // MARK: - Derived components

    /// The year a record is filed under, in every per-year statistic, filter and
    /// Year in Review alike, so each record counts in exactly one year (D-23).
    ///
    /// A range that crosses New Year belongs to the year it began, as a trip does: a
    /// 28 December to 3 January holiday is that year's holiday.
    public var year: Int? {
        switch self {
        case let .day(date): date.year
        case let .range(start, _): start.year
        case let .month(year, _): year
        case let .year(year): year
        case .unknown: nil
        }
    }

    /// The month, where exactly one month is implied.
    ///
    /// A range that straddles two months has no single month, which matters for the
    /// climate-normal stat (R-CALC-2) — it needs one month or it falls back.
    public var month: Int? {
        switch self {
        case let .day(date): date.month
        case let .range(start, end):
            (start.year == end.year && start.month == end.month) ? start.month : nil
        case let .month(_, month): month
        case .year, .unknown: nil
        }
    }

    /// The first day, where the date is known to the day — a day, or the start of a
    /// range. `nil` for a month, a year or unknown.
    ///
    /// For anything that claims "on this day": a badge earned on 1 January 2019 because
    /// a visit was dated only "2019" would be a made-up date.
    public var exactStartDay: CalendarDate? {
        switch self {
        case let .day(date): date
        case let .range(start, _): start
        case .month, .year, .unknown: nil
        }
    }

    /// The month a record is filed under for seasonality: the month itself, or the
    /// month a range began in (D-23). `nil` for a year or unknown.
    public var startMonth: Int? {
        switch self {
        case let .day(date): date.month
        case let .range(start, _): start.month
        case let .month(_, month): month
        case .year, .unknown: nil
        }
    }

    /// Earliest day this date could refer to.
    public var earliestDay: CalendarDate? {
        switch self {
        case let .day(date): date
        case let .range(start, _): start
        case let .month(year, month): CalendarDate(year: year, month: month, day: 1)
        case let .year(year): CalendarDate(year: year, month: 1, day: 1)
        case .unknown: nil
        }
    }

    /// Latest day this date could refer to.
    public var latestDay: CalendarDate? {
        switch self {
        case let .day(date): date
        case let .range(_, end): end
        case let .month(year, month):
            CalendarDate(
                year: year,
                month: month,
                day: CalendarDate.daysIn(month: month, year: year)
            )
        case let .year(year): CalendarDate(year: year, month: 12, day: 31)
        case .unknown: nil
        }
    }

    /// The day used when a stat must order or bucket by a single point in time.
    ///
    /// For imprecise dates this is the earliest possible day, which keeps ordering
    /// stable and never places a visit before something that genuinely preceded it.
    public var sortDay: CalendarDate? {
        earliestDay
    }

    /// Number of days the date definitely covers, where that is known.
    ///
    /// `nil` for a month or a year: the user did not say they were there all month.
    public var knownDayCount: Int? {
        switch self {
        case .day: 1
        case let .range(start, end): start.days(to: end) + 1
        case .month, .year, .unknown: nil
        }
    }

    // MARK: - Serialisation

    /// Compact text form, used by CSV export and import.
    ///
    /// `2024-06-12` · `2024-06-12/2024-06-20` · `2024-06` · `2024` · `` (unknown)
    public var exportString: String {
        switch self {
        case let .day(date): date.iso
        case let .range(start, end): "\(start.iso)/\(end.iso)"
        case let .month(year, month): String(format: "%04d-%02d", year, month)
        case let .year(year): String(format: "%04d", year)
        case .unknown: ""
        }
    }

    /// Parses `exportString`. Returns `.unknown` for empty input, `nil` for malformed.
    public static func parse(_ text: String) -> FlexibleDate? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .unknown
        }

        if trimmed.contains("/") {
            let halves = trimmed.split(separator: "/")
            guard halves.count == 2,
                  let start = CalendarDate(iso: String(halves[0])),
                  let end = CalendarDate(iso: String(halves[1]))
            else { return nil }
            return .span(start, end)
        }

        let parts = trimmed.split(separator: "-")
        switch parts.count {
        case 1:
            guard parts[0].count == 4, let year = Int(parts[0]) else { return nil }
            return .year(year)
        case 2:
            guard parts[0].count == 4, parts[1].count == 2,
                  let year = Int(parts[0]), let month = Int(parts[1]),
                  (1 ... 12).contains(month)
            else { return nil }
            return .month(year: year, month: month)
        case 3:
            guard let date = CalendarDate(iso: trimmed) else { return nil }
            return .day(date)
        default:
            return nil
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey { case value }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .value)
        guard let parsed = FlexibleDate.parse(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: .value,
                in: container,
                debugDescription: "Not a flexible date: \(text)"
            )
        }
        self = parsed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exportString, forKey: .value)
    }
}

extension FlexibleDate: Comparable {
    /// Orders by earliest possible day; unknown dates sort last.
    public static func < (lhs: FlexibleDate, rhs: FlexibleDate) -> Bool {
        switch (lhs.sortDay, rhs.sortDay) {
        case let (left?, right?): left < right
        case (nil, _?): false
        case (_?, nil): true
        case (nil, nil): false
        }
    }
}
