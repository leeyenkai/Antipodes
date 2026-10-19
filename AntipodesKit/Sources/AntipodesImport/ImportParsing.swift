import AntipodesCore
import Foundation

/// Pulls an airport code out of the many ways exports write an airport.
public enum AirportCode {
    /// `OSL`, `ENGM`, `Oslo (OSL)`, `Oslo / Oslo Gardermoen (OSL/ENGM)`, `OSL - Oslo`.
    /// IATA is preferred over ICAO where both are present.
    public static func extract(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if isCode(trimmed) {
            return trimmed.uppercased()
        }
        // Inside brackets first: "(OSL/ENGM)".
        if let open = trimmed.lastIndex(of: "("), let close = trimmed.lastIndex(of: ")"),
           open < close {
            let inside = trimmed[trimmed.index(after: open) ..< close]
            let parts = inside.split(whereSeparator: { $0 == "/" || $0 == "," || $0 == " " })
                .map(String.init)
            if let iata = parts.first(where: { $0.count == 3 && isCode($0) }) {
                return iata.uppercased()
            }
            if let icao = parts.first(where: { $0.count == 4 && isCode($0) }) {
                return icao.uppercased()
            }
        }
        // Then a standalone uppercase token: "OSL - Oslo".
        let tokens = trimmed.split(whereSeparator: { !$0.isLetter }).map(String.init)
        if let token = tokens
            .first(where: { $0.count == 3 && $0 == $0.uppercased() && isCode($0) }) {
            return token
        }
        return nil
    }

    static func isCode(_ text: String) -> Bool {
        (3 ... 4).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isLetter }
            && (text == text.uppercased() || text.count == 3)
    }
}

/// Reading the date and time formats exports use.
enum DateText {
    /// Settles day-first versus month-first from the values themselves.
    static func dayFirst(in values: [String], fallback: Bool) -> Bool {
        for value in values {
            let parts = slashParts(value)
            guard parts.count == 3 else { continue }
            if parts[0] > 12 {
                return true
            }
            if parts[1] > 12 {
                return false
            }
        }
        return fallback
    }

    static func slashParts(_ value: String) -> [Int] {
        let datePart = value.split(separator: " ").first.map(String.init) ?? value
        guard datePart.contains("/") || datePart.contains(".") else { return [] }
        return datePart.split(whereSeparator: { $0 == "/" || $0 == "." }).compactMap { Int($0) }
    }

    /// A day, and a time of day if the value carries one.
    static func parse(_ value: String, dayFirst: Bool) -> (day: CalendarDate, time: (Int, Int)?)? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let pieces = trimmed.split(whereSeparator: { $0 == " " || $0 == "T" }).map(String.init)
        guard let datePart = pieces.first else { return nil }
        let clock = pieces.count > 1 ? clockTime(pieces[1]) : nil

        if let iso = CalendarDate(iso: String(datePart.prefix(10))) {
            return (iso, clock)
        }
        let parts = slashParts(datePart)
        if parts.count == 3 {
            var (first, second, year) = (parts[0], parts[1], parts[2])
            if year < 100 {
                year += year < 70 ? 2000 : 1900
            }
            if !dayFirst {
                swap(&first, &second)
            }
            if let day = CalendarDate(year: year, month: second, day: first) {
                return (day, clock)
            }
        }
        return nil
    }

    static func clockTime(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":").compactMap { Int($0.prefix(2)) }
        guard parts.count >= 2, (0 ... 23).contains(parts[0]), (0 ... 59).contains(parts[1]) else {
            return nil
        }
        return (parts[0], parts[1])
    }

    /// A time column: either a full date-time, or a bare time on the row's own day.
    static func time(_ value: String, on day: CalendarDate?, dayFirst: Bool) -> LocalDateTime? {
        if let parsed = parse(value, dayFirst: dayFirst), let clock = parsed.time {
            return LocalDateTime(date: parsed.day, hour: clock.0, minute: clock.1)
        }
        if let day, let clock = clockTime(value) {
            return LocalDateTime(date: day, hour: clock.0, minute: clock.1)
        }
        return nil
    }
}

extension LocalDateTime {
    var nextDay: LocalDateTime? {
        date.adding(days: 1).flatMap { LocalDateTime(date: $0, hour: hour, minute: minute) }
    }
}
