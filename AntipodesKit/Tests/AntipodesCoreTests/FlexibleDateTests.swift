import AntipodesCore
import Foundation
import Testing

@Suite("Calendar dates")
struct CalendarDateTests {
    @Test("Impossible dates are rejected rather than rolled over")
    func validation() {
        #expect(CalendarDate(year: 2024, month: 2, day: 30) == nil)
        #expect(CalendarDate(year: 2023, month: 2, day: 29) == nil)
        #expect(CalendarDate(year: 2024, month: 2, day: 29) != nil) // leap year
        #expect(CalendarDate(year: 2024, month: 13, day: 1) == nil)
        #expect(CalendarDate(year: 2024, month: 4, day: 31) == nil)
        #expect(CalendarDate(year: 2024, month: 0, day: 1) == nil)
    }

    @Test("Leap years follow the Gregorian rule, centuries included")
    func leapYears() {
        #expect(CalendarDate.isLeapYear(2024))
        #expect(!CalendarDate.isLeapYear(2023))
        #expect(!CalendarDate.isLeapYear(1900))
        #expect(CalendarDate.isLeapYear(2000))
    }

    @Test("ISO parsing requires a full YYYY-MM-DD")
    func isoParsing() {
        #expect(CalendarDate(iso: "2024-06-12")?.day == 12)
        #expect(CalendarDate(iso: "2024-6-12") == nil)
        #expect(CalendarDate(iso: "2024-06") == nil)
        #expect(CalendarDate(iso: "not a date") == nil)
        #expect(CalendarDate(year: 2024, month: 6, day: 12)?.iso == "2024-06-12")
    }

    /// Hand-computed: 1 January 1970 is day 0, so 2 January is day 1 and
    /// 31 December 1969 is day −1.
    @Test("Days since the epoch are exact around the epoch")
    func epochBoundary() {
        #expect(CalendarDate(year: 1970, month: 1, day: 1)?.daysSinceEpoch == 0)
        #expect(CalendarDate(year: 1970, month: 1, day: 2)?.daysSinceEpoch == 1)
        #expect(CalendarDate(year: 1969, month: 12, day: 31)?.daysSinceEpoch == -1)
    }

    /// 2024 is a leap year, so 1 January to 31 December is 365 days apart.
    @Test("Day differences span leap years correctly")
    func dayDifferences() throws {
        let start = try #require(CalendarDate(year: 2024, month: 1, day: 1))
        let end = try #require(CalendarDate(year: 2024, month: 12, day: 31))
        #expect(start.days(to: end) == 365)
        #expect(end.days(to: start) == -365)

        let marchFirst = try #require(CalendarDate(year: 2024, month: 3, day: 1))
        #expect(start.days(to: marchFirst) == 60) // 31 January + 29 February
    }

    @Test("Dates order chronologically")
    func ordering() throws {
        let earlier = try #require(CalendarDate(year: 2023, month: 12, day: 31))
        let later = try #require(CalendarDate(year: 2024, month: 1, day: 1))
        #expect(earlier < later)
    }
}

@Suite("Flexible dates")
struct FlexibleDateTests {
    @Test("Precision reflects what the user actually said")
    func precision() throws {
        let day = try #require(CalendarDate(iso: "2024-06-12"))
        #expect(FlexibleDate.day(day).precision == .day)
        #expect(FlexibleDate.month(year: 2024, month: 6).precision == .month)
        #expect(FlexibleDate.year(2024).precision == .year)
        #expect(FlexibleDate.unknown.precision == .unknown)
        #expect(!FlexibleDate.unknown.isKnown)
        #expect(FlexibleDate.year(2024).isKnown)
    }

    @Test("A reversed range is normalised rather than rejected")
    func rangeNormalisation() throws {
        let first = try #require(CalendarDate(iso: "2024-06-20"))
        let second = try #require(CalendarDate(iso: "2024-06-12"))
        guard case let .range(start, end) = FlexibleDate.span(first, second) else {
            Issue.record("span did not produce a range")
            return
        }
        #expect(start.iso == "2024-06-12")
        #expect(end.iso == "2024-06-20")
    }

    @Test("A month expands to its first and last day, leap year included")
    func monthBounds() {
        let february = FlexibleDate.month(year: 2024, month: 2)
        #expect(february.earliestDay?.iso == "2024-02-01")
        #expect(february.latestDay?.iso == "2024-02-29")

        let nonLeap = FlexibleDate.month(year: 2023, month: 2)
        #expect(nonLeap.latestDay?.iso == "2023-02-28")
    }

    @Test("A year expands to 1 January and 31 December")
    func yearBounds() {
        #expect(FlexibleDate.year(2024).earliestDay?.iso == "2024-01-01")
        #expect(FlexibleDate.year(2024).latestDay?.iso == "2024-12-31")
    }

    @Test("An unknown date has no bounds at all")
    func unknownHasNoBounds() {
        #expect(FlexibleDate.unknown.earliestDay == nil)
        #expect(FlexibleDate.unknown.latestDay == nil)
        #expect(FlexibleDate.unknown.year == nil)
        #expect(FlexibleDate.unknown.month == nil)
        #expect(FlexibleDate.unknown.knownDayCount == nil)
    }

    /// The climate-normal stat needs exactly one month (R-CALC-2), so a range that
    /// straddles two must report none rather than picking one.
    @Test("A range inside one month has a month; a range across two does not")
    func monthFromRange() throws {
        let sameMonth = try FlexibleDate.span(
            #require(CalendarDate(iso: "2024-06-01")),
            #require(CalendarDate(iso: "2024-06-20"))
        )
        #expect(sameMonth.month == 6)
        #expect(sameMonth.year == 2024)

        let straddling = try FlexibleDate.span(
            #require(CalendarDate(iso: "2024-06-28")),
            #require(CalendarDate(iso: "2024-07-03"))
        )
        #expect(straddling.month == nil)
        #expect(straddling.year == 2024)

        let acrossYears = try FlexibleDate.span(
            #require(CalendarDate(iso: "2024-12-28")),
            #require(CalendarDate(iso: "2025-01-03"))
        )
        #expect(acrossYears.year == nil)
    }

    /// A month is not a claim to have been there all month, so it has no known day
    /// count. Treating it as 30 days would inflate "days away per year".
    @Test("Only a day or a range has a known day count")
    func knownDayCount() throws {
        let day = try #require(CalendarDate(iso: "2024-06-12"))
        #expect(FlexibleDate.day(day).knownDayCount == 1)

        let range = try FlexibleDate.span(
            day,
            #require(CalendarDate(iso: "2024-06-20"))
        )
        #expect(range.knownDayCount == 9) // inclusive of both ends

        #expect(FlexibleDate.month(year: 2024, month: 6).knownDayCount == nil)
        #expect(FlexibleDate.year(2024).knownDayCount == nil)
    }

    @Test("Export strings round-trip at every precision")
    func roundTrip() throws {
        let cases: [FlexibleDate] = try [
            .day(#require(CalendarDate(iso: "2024-06-12"))),
            .span(
                #require(CalendarDate(iso: "2024-06-12")),
                #require(CalendarDate(iso: "2024-06-20"))
            ),
            .month(year: 2024, month: 6),
            .year(2024),
            .unknown,
        ]
        for original in cases {
            let text = original.exportString
            #expect(FlexibleDate.parse(text) == original, "round trip failed for \(text)")
        }
    }

    @Test("Export strings are the documented shapes")
    func exportShapes() throws {
        #expect(try FlexibleDate.day(#require(CalendarDate(iso: "2024-06-12")))
            .exportString == "2024-06-12")
        #expect(FlexibleDate.month(year: 2024, month: 6).exportString == "2024-06")
        #expect(FlexibleDate.year(2024).exportString == "2024")
        // swiftlint:disable:next empty_string - an unknown date IS the empty string
        #expect(FlexibleDate.unknown.exportString == "")
    }

    @Test("Malformed text fails; empty text is an unknown date")
    func parseFailures() {
        #expect(FlexibleDate.parse("") == .unknown)
        #expect(FlexibleDate.parse("   ") == .unknown)
        #expect(FlexibleDate.parse("2024-13") == nil)
        #expect(FlexibleDate.parse("24-06-12") == nil)
        #expect(FlexibleDate.parse("2024-02-30") == nil)
        #expect(FlexibleDate.parse("sometime") == nil)
        #expect(FlexibleDate.parse("2024-06-12/notadate") == nil)
    }

    @Test("Codable round-trips through the compact string form")
    func codable() throws {
        let original = FlexibleDate.month(year: 2024, month: 6)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(FlexibleDate.self, from: data) == original)
    }

    /// Unknown dates sort last so an undated visit never jumps to the top of a
    /// chronological list.
    @Test("Dates order by earliest possible day, unknown last")
    func sorting() throws {
        let sorted: [FlexibleDate] = try [
            .unknown,
            .day(#require(CalendarDate(iso: "2024-06-12"))),
            .year(2020),
            .month(year: 2024, month: 1),
        ].sorted()

        #expect(sorted[0] == .year(2020))
        #expect(sorted[1] == .month(year: 2024, month: 1))
        #expect(sorted[2].precision == .day)
        #expect(sorted[3] == .unknown)
    }
}

@Suite("Counting rules")
struct CountingRulesTests {
    /// R-CALC-1: stayed and day trips count; passed through and layovers do not.
    @Test("Default rules count stays and day trips only")
    func defaults() {
        let rules = CountingRules.default
        #expect(rules.countsTowardsCoverage(.stayed))
        #expect(rules.countsTowardsCoverage(.dayTrip))
        #expect(!rules.countsTowardsCoverage(.passedThrough))
        #expect(!rules.countsTowardsCoverage(.layover))
    }

    @Test("Switching a rule on changes what counts")
    func overrides() {
        var rules = CountingRules.default
        rules.includePassedThrough = true
        #expect(rules.countsTowardsCoverage(.passedThrough))
        #expect(!rules.countsTowardsCoverage(.layover))

        rules.includeLayovers = true
        #expect(rules.countsTowardsCoverage(.layover))
    }

    @Test("Commutes are out of stats until switched in")
    func commutes() {
        var rules = CountingRules.default
        #expect(rules.countsInStats(.leisure))
        #expect(rules.countsInStats(.work))
        #expect(!rules.countsInStats(.commute))

        rules.includeCommutes = true
        #expect(rules.countsInStats(.commute))
    }

    @Test("The visit type's own default matches the default rules")
    func visitTypeDefaultsAgree() {
        for type in VisitType.allCases {
            #expect(
                CountingRules.default.countsTowardsCoverage(type)
                    == type.countsTowardsCoverageByDefault
            )
        }
    }

    /// 100 km is 62.137 miles; 20 °C is 68 °F.
    @Test("Unit conversion uses the exact statute mile")
    func unitConversion() {
        #expect(abs(UnitSystem.imperial.distance(fromKilometres: 100) - 62.137_1) < 0.001)
        #expect(UnitSystem.metric.distance(fromKilometres: 100) == 100)
        #expect(UnitSystem.imperial.temperature(fromCelsius: 20) == 68)
        #expect(UnitSystem.imperial.temperature(fromCelsius: -40) == -40)
        #expect(UnitSystem.metric.temperature(fromCelsius: 20) == 20)
    }

    @Test("The world-country denominator can never be zero")
    func denominatorGuard() {
        #expect(CountingRules(worldCountryCount: 0).worldCountryCount == 1)
        #expect(CountingRules(worldCountryCount: -5).worldCountryCount == 1)
    }
}
