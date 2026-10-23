import AntipodesCore
import Foundation

/// Every number and date the app shows, formatted in one place so a distance reads the
/// same on the globe, in a list and on a share card (R-CALC-4).
enum Format {
    static func distance(
        _ kilometres: Double,
        _ system: UnitSystem,
        approximate: Bool = false
    ) -> String {
        let value = system.distance(fromKilometres: kilometres)
        let number = value >= 100 || value == 0
            ? whole(value)
            : value.formatted(.number.precision(.fractionLength(1)))
        return "\(approximate ? "≈ " : "")\(number) \(system.distanceUnitAbbreviation)"
    }

    /// "8h 30m", "45m", "3d 4h".
    static func duration(minutes: Int) -> String {
        let minutes = max(0, minutes)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let rest = minutes % 60
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return rest > 0 ? "\(hours)h \(rest)m" : "\(hours)h"
        }
        return "\(rest)m"
    }

    /// Hours and minutes with no days, the way flight time is quoted: "74h 30m".
    static func hours(minutes: Int) -> String {
        let minutes = max(0, minutes)
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours.formatted())h" : "\(hours.formatted())h \(rest)m"
    }

    /// "142 kg" below a tonne, "1.4 t" above.
    static func carbon(kilograms: Double) -> String {
        if abs(kilograms) >= 1000 {
            return "\((kilograms / 1000).formatted(.number.precision(.fractionLength(1)))) t CO₂e"
        }
        return "\(whole(kilograms)) kg CO₂e"
    }

    static func elevation(_ metres: Double, _ system: UnitSystem) -> String {
        switch system {
        case .metric: "\(whole(metres)) m"
        case .imperial: "\(whole(metres / 0.3048)) ft"
        }
    }

    /// "17 °C" or "63 °F", to the whole degree: a climate normal is not more precise.
    static func temperature(_ celsius: Double, _ system: UnitSystem) -> String {
        let value = whole(system.temperature(fromCelsius: celsius))
        return "\(value) \(system == .metric ? "°C" : "°F")"
    }

    /// A figure to the whole unit, grouped: "12,345". Formatted as a floating-point
    /// number rather than through `Int`, which traps on anything too large to hold —
    /// and "—" for a figure that is not a number at all, rather than "∞" or "NaN".
    static func whole(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        // Adding zero turns the -0 that rounding -0.4 gives into a plain 0.
        return (value.rounded() + 0).formatted(.number.precision(.fractionLength(0)))
    }

    static func compact(_ value: Double) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(2)))
    }

    /// "7", "640", "1.2K": exact below a thousand, where a rounded count would look wrong.
    static func compactCount(_ count: Int) -> String {
        count < 1000 ? count.formatted() : compact(Double(count))
    }

    /// "1.43×", for how many times a distance would go round the Earth.
    static func multiple(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(2))))×"
    }

    static func percent(_ fraction: Double, digits: Int = 1) -> String {
        fraction.formatted(.percent.precision(.fractionLength(digits)))
    }

    static func delay(minutes: Double) -> String {
        guard minutes.isFinite else { return "—" }
        let rounded = Int(max(-99999, min(99999, minutes)).rounded())
        if rounded == 0 {
            return "on time"
        }
        return rounded > 0 ? "\(rounded) min late" : "\(-rounded) min early"
    }

    /// A year with its era: "AD 82", "447 BC".
    static func year(_ year: Int) -> String {
        year < 0 ? "\(-year) BC" : (year < 1000 ? "AD \(year)" : String(year))
    }

    static func years(_ value: Double) -> String {
        "\(whole(value)) years"
    }

    /// 🇳🇴 from "NO". Regional indicator symbols, so it needs no image and no network.
    static func flag(_ code: String?) -> String {
        guard let code, code.count == 2 else { return "🏳️" }
        let base: UInt32 = 127_397
        return code.uppercased().unicodeScalars
            .compactMap { UnicodeScalar(base + $0.value) }
            .map(String.init)
            .joined()
    }

    static func countryName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    static func currencyName(_ code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    /// The log's dates are Gregorian whatever calendar the device uses, so they are
    /// named and formatted in Gregorian too, in the reader's language. Otherwise a
    /// Hebrew or Islamic calendar would name the wrong month and a Buddhist one would
    /// put 2567 beside a trip filed under 2024.
    static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar
    }()

    static func monthName(_ month: Int) -> String {
        gregorian.monthSymbols[max(0, min(11, month - 1))]
    }

    static func shortMonthName(_ month: Int) -> String {
        gregorian.shortMonthSymbols[max(0, min(11, month - 1))]
    }

    /// Calendar dates are converted at midnight GMT, so they are formatted in GMT too —
    /// otherwise a date shows as the day before for anyone west of Greenwich.
    private static func gmt(_ style: Date.FormatStyle) -> Date.FormatStyle {
        var style = style
        style.timeZone = .gmt
        style.calendar = gregorian
        return style
    }

    static func day(_ date: CalendarDate) -> String {
        date.date()?.formatted(gmt(.dateTime.day().month(.abbreviated).year())) ?? date.iso
    }

    static func shortDay(_ date: CalendarDate) -> String {
        date.date()?.formatted(gmt(.dateTime.day().month(.abbreviated))) ?? date.iso
    }

    /// A span of days in the reader's own order — "12–20 Jun 2024" or "Jun 12 – 20,
    /// 2024" — sharing the month and year where they are the same.
    static func span(_ start: CalendarDate, _ end: CalendarDate) -> String {
        guard start < end, let from = start.date(), let to = end.date() else {
            return day(start)
        }
        return (from ..< to).formatted(
            Date.IntervalFormatStyle(
                date: .abbreviated,
                time: .omitted,
                calendar: gregorian,
                timeZone: .gmt
            )
        )
    }

    static func ordinalCount(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count.formatted()) \(count == 1 ? singular : plural ?? singular + "s")"
    }

    /// How long ago, in the largest unit that is at least one: "3 years", "5 months",
    /// "12 days". Never "0 years".
    static func elapsed(days: Int) -> String {
        let days = max(0, days)
        if days >= 365 {
            return ordinalCount(days / 365, "year")
        }
        if days >= 31 {
            return ordinalCount(days / 30, "month")
        }
        return ordinalCount(days, "day")
    }
}

extension FlexibleDate {
    /// Human-readable form for lists and detail views.
    var displayText: String {
        switch self {
        case let .day(date): Format.day(date)
        case let .range(start, end): Format.span(start, end)
        case let .month(year, month): "\(Format.monthName(month)) \(String(year))"
        case let .year(year): String(year)
        case .unknown: "Date unknown"
        }
    }
}

extension LocalDateTime {
    var displayText: String {
        "\(Format.shortDay(date)), \(clockText)"
    }
}
