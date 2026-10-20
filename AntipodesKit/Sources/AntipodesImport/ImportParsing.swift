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
        // Then a standalone uppercase token: "OSL - Oslo". In a name written all in
        // capitals every word looks like one — "NEW YORK JFK" — and the code is the
        // one that comes last.
        let tokens = trimmed.split(whereSeparator: { !$0.isLetter }).map(String.init)
            .filter { $0.count == 3 && $0 == $0.uppercased() && isCode($0) }
        let shouting = trimmed == trimmed.uppercased()
        return shouting ? tokens.last : tokens.first
    }

    static func isCode(_ text: String) -> Bool {
        (3 ... 4).contains(text.count) && text.allSatisfy { $0.isASCII && $0.isLetter }
            && (text == text.uppercased() || text.count == 3)
    }
}

/// Reading the date and time formats exports use.
enum DateText {
    /// Settles day-first versus month-first from the values themselves. A value that
    /// starts with its year, `2024/06/12`, says nothing about the order of the other two.
    static func dayFirst(in values: [String], fallback: Bool) -> Bool {
        for value in values {
            let parts = slashParts(value)
            guard parts.count == 3, parts[0] < 1000 else { continue }
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
    static func parse(_ value: String, dayFirst: Bool) -> (day: CalendarDate, time: ClockTime?)? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let pieces = trimmed.split(whereSeparator: { $0 == " " || $0 == "T" }).map(String.init)
        guard let datePart = pieces.first else { return nil }
        // The rest is the clock, with any "PM" that followed it after a space.
        let clock = pieces.count > 1 ? clockTime(pieces.dropFirst().joined(separator: " ")) : nil

        if let iso = CalendarDate(iso: String(datePart.prefix(10))) {
            return (iso, clock)
        }
        let parts = slashParts(datePart)
        if parts.count == 3, parts[0] >= 1000 {
            // Year first, as in 2024/06/12: always year, month, day.
            return CalendarDate(year: parts[0], month: parts[1], day: parts[2]).map { ($0, clock) }
        }
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

    /// A time of day as an export writes it: `08:35`, `08:35:00`, `8:35 PM`, or with a
    /// zone — `08:35Z`, `08:35+02:00` — which is kept, so the time can be moved to the
    /// airport's own clock once the airport is known.
    static func clockTime(_ text: String) -> ClockTime? {
        var rest = text.trimmingCharacters(in: .whitespaces).uppercased()
        var afternoon: Bool?
        for (marker, isPM) in [("A.M.", false), ("P.M.", true), ("AM", false), ("PM", true)]
            where rest.hasSuffix(marker) {
            afternoon = isPM
            rest = String(rest.dropLast(marker.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        var offsetMinutes: Int?
        if rest.hasSuffix("Z") {
            offsetMinutes = 0
            rest.removeLast()
        } else if let sign = rest.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            let digits = rest[rest.index(after: sign)...].filter(\.isNumber)
            guard digits.count == 4 || digits.count == 2,
                  let value = Int(digits) else { return nil }
            let minutes = digits.count == 4 ? (value / 100) * 60 + value % 100 : value * 60
            offsetMinutes = rest[sign] == "-" ? -minutes : minutes
            rest = String(rest[..<sign])
        }

        let parts = rest.split(separator: ":").compactMap { Int($0.prefix(2)) }
        guard parts.count >= 2, (0 ... 59).contains(parts[1]) else { return nil }
        var hour = parts[0]
        if let afternoon {
            guard (1 ... 12).contains(hour) else { return nil }
            hour = hour % 12 + (afternoon ? 12 : 0)
        }
        guard (0 ... 23).contains(hour) else { return nil }
        return ClockTime(hour: hour, minute: parts[1], offsetMinutes: offsetMinutes)
    }

    /// A time column: either a full date-time, or a bare time on the row's own day.
    static func time(_ value: String, on day: CalendarDate?, dayFirst: Bool) -> StampedTime? {
        if let parsed = parse(value, dayFirst: dayFirst), let clock = parsed.time {
            return clock.on(parsed.day)
        }
        if let day, let clock = clockTime(value) {
            return clock.on(day)
        }
        return nil
    }

    /// A duration column: `07:35`, `07:35:00`, or a plain number of minutes.
    static func durationMinutes(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if let minutes = Int(trimmed) {
            return minutes > 0 ? minutes : nil
        }
        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2, (0 ... 59).contains(parts[1]) else { return nil }
        let minutes = parts[0] * 60 + parts[1]
        return minutes > 0 ? minutes : nil
    }
}

/// A clock reading, and the UTC offset written beside it if there was one.
struct ClockTime: Hashable, Sendable {
    let hour: Int
    let minute: Int
    let offsetMinutes: Int?

    func on(_ day: CalendarDate) -> StampedTime? {
        LocalDateTime(date: day, hour: hour, minute: minute)
            .map { StampedTime(time: $0, offsetMinutes: offsetMinutes) }
    }
}

/// A time as the file wrote it. `offsetMinutes` is set when the file named a zone — a
/// `Z` or `+02:00` — and is then the only correct way to read the time.
public struct StampedTime: Hashable, Sendable {
    public var time: LocalDateTime
    public var offsetMinutes: Int?

    /// The same moment on the wall clock of `zone`: what a ticket at that airport says.
    /// A time with no offset of its own is already local and comes back unchanged.
    func local(in zone: TimeZone?) -> LocalDateTime {
        guard let offsetMinutes, let zone,
              let written = TimeZone(secondsFromGMT: offsetMinutes * 60),
              let instant = time.instant(in: written)
        else { return time }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        guard let year = parts.year, let month = parts.month, let day = parts.day,
              let date = CalendarDate(year: year, month: month, day: day),
              let local = LocalDateTime(
                  date: date,
                  hour: parts.hour ?? 0,
                  minute: parts.minute ?? 0
              )
        else { return time }
        return local
    }
}

extension LocalDateTime {
    var nextDay: LocalDateTime? {
        date.adding(days: 1).flatMap { LocalDateTime(date: $0, hour: hour, minute: minute) }
    }
}
