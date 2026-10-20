import AntipodesCore
@testable import AntipodesImport
import Foundation
import Testing

@Suite("Import edge cases")
struct ImportEdgeCaseTests {
    static let osl = FlightLogImportTests.airport("OSL", zone: "Europe/Oslo")
    static let jfk = FlightLogImportTests.airport("JFK", zone: "America/New_York")
    static let lax = FlightLogImportTests.airport("LAX", zone: "America/Los_Angeles")
    static let syd = FlightLogImportTests.airport("SYD", zone: "Australia/Sydney")
    static let airports = ["OSL": osl, "JFK": jfk, "LAX": lax, "SYD": syd]

    static func candidates(_ csv: String, existing: [JourneyLeg] = []) async throws
        -> [FlightImportCandidate] {
        let (_, rows) = try FlightLogImport.parse(Data(csv.utf8), dayFirst: true)
        return await FlightLogImport.match(rows, existing: existing) { airports[$0] }
    }

    // MARK: - CSV

    @Test("A quoted field after a space still opens a quote")
    func quoteAfterSpace() throws {
        #expect(try CSVReader.rows(from: "a, \"b, c\"\n") == [["a", "b, c"]])
    }

    /// Excel's "Unicode text" is UTF-16 with a byte-order mark; read as Latin-1 it is
    /// every other byte a NUL.
    @Test("UTF-16 with a byte-order mark is read as UTF-16")
    func utf16() throws {
        let data = try #require("date,from,to\n2024-01-01,OSL,JFK\n".data(using: .utf16))
        #expect(try CSVReader.rows(from: data) == [
            ["date", "from", "to"],
            ["2024-01-01", "OSL", "JFK"],
        ])
    }

    // MARK: - Dates and times

    @Test("A year-first slash date is year, month, day and does not make the file day-first")
    func yearFirstSlashes() throws {
        let csv = "date,from,to\n2024/06/12,OSL,JFK\n03/04/2021,JFK,OSL\n"
        let (_, rows) = try FlightLogImport.parse(Data(csv.utf8), dayFirst: false)
        #expect(rows.first?.date.exportString == "2024-06-12")
        // Nothing decided the order, so the device's month-first convention stands.
        #expect(rows.last?.date.exportString == "2021-03-04")
    }

    @Test("Twelve-hour clocks are read with their AM or PM")
    func twelveHourClock() throws {
        let csv = "date,from,to,dep time,arr time\n2024-06-12,OSL,JFK,8:35 PM,11:10 pm\n"
        let (_, rows) = try FlightLogImport.parse(Data(csv.utf8), dayFirst: true)
        #expect(rows.first?.times.scheduledDeparture?.iso == "2024-06-12T20:35")
        #expect(rows.first?.times.scheduledArrival?.iso == "2024-06-12T23:10")
        #expect(DateText.clockTime("12:05 AM").map { [$0.hour, $0.minute] } == [0, 5])
        #expect(DateText.clockTime("13:05 PM") == nil)
    }

    /// 08:35Z is 10:35 in Oslo in June (CEST, UTC+2); 16:00-04:00 is 16:00 in New York
    /// in June (EDT, UTC−4) and stays put.
    @Test("A time stamped with a zone is moved to the airport's own clock")
    func zonedTimes() async throws {
        let csv = """
        date,from,to,dep time,arr time
        2024-06-12,OSL,JFK,2024-06-12T08:35Z,2024-06-12T16:00-04:00
        """
        let leg = try #require(try await Self.candidates(csv).first?.leg)
        #expect(leg.times.scheduledDeparture?.iso == "2024-06-12T10:35")
        #expect(leg.times.scheduledArrival?.iso == "2024-06-12T16:00")
    }

    /// LAX 22:00 (PDT, 05:00Z next day) to SYD 06:00 (AEST, UTC+10). Read on the same
    /// day the arrival is 20:00Z the day before; one day on it is still before
    /// departure; two days on it is 20:00Z on the 13th, a 15-hour flight.
    @Test("A westbound flight over the date line can land two days later")
    func twoDayArrival() async throws {
        let csv = "date,from,to,dep time,arr time\n2024-06-11,LAX,SYD,22:00,06:00\n"
        let leg = try #require(try await Self.candidates(csv).first?.leg)
        #expect(leg.times.scheduledArrival?.iso == "2024-06-13T06:00")
        #expect(leg.durationMinutes == 15 * 60)
    }

    @Test("A stated flight time stands in when there are no times")
    func statedDuration() async throws {
        let csv = "date,from,to,duration\n2024-06-12,OSL,JFK,08:30:00\n"
        let leg = try #require(try await Self.candidates(csv).first?.leg)
        #expect(leg.durationMinutes == 510)
        #expect(DateText.durationMinutes("95") == 95)
        #expect(DateText.durationMinutes("0") == nil)
    }

    // MARK: - Airports

    @Test("In a name written all in capitals, the code is the last word")
    func shoutedNames() {
        #expect(AirportCode.extract(from: "NEW YORK JFK") == "JFK")
        #expect(AirportCode.extract(from: "OSL - OSLO") == "OSL")
        #expect(AirportCode.extract(from: "JFK - New York") == "JFK")
    }

    // MARK: - Flighty

    @Test("A cancelled flight is shown but not imported, and a diversion lands where it landed")
    func cancelledAndDiverted() async throws {
        let csv = """
        Date,Airline,Flight,From,To,Canceled,Diverted To,Gate Departure (Scheduled)
        2024-06-12,SAS,SK903,OSL,JFK,true,,2024-06-12T09:00
        2024-06-13,SAS,SK905,OSL,LAX,false,JFK,2024-06-13T09:00
        """
        let found = try await Self.candidates(csv)
        #expect(found.first?.status == .cancelled)
        #expect(found.first?.include == false)
        #expect(found.last?.destination?.code == "JFK")
        #expect(found.last?.row.notes == "Diverted; scheduled to LAX.")
        #expect(found.last?.include == true)
    }

    // MARK: - Duplicates

    static func existingFlight(_ number: String?) throws -> JourneyLeg {
        try JourneyLeg(
            mode: .flight, origin: osl, destination: jfk,
            date: .day(#require(CalendarDate(iso: "2024-06-12"))),
            serviceNumber: number
        )
    }

    /// A flight logged by hand without a number is the same trip as the SK903 an
    /// import finds on that day and route.
    @Test("A missing flight number matches any number on the same day and route")
    func numberlessDuplicates() async throws {
        let csv = "date,from,to,flight\n2024-06-12,OSL,JFK,SK903\n"
        #expect(try await Self.candidates(csv, existing: [Self.existingFlight(nil)]).first?.status
            == .duplicate)
        #expect(try await Self.candidates(csv, existing: [Self.existingFlight("SK 903")]).first?
            .status
            == .duplicate)
        // Two different numbers are two flights.
        #expect(try await Self.candidates(csv, existing: [Self.existingFlight("DY7001")]).first?
            .status
            == .ready)
    }

    @Test("The same flight twice in one file is imported once")
    func duplicatesWithinFile() async throws {
        let csv = "date,from,to,flight\n2024-06-12,OSL,JFK,SK903\n2024-06-12,OSL,JFK,SK903\n"
        let found = try await Self.candidates(csv)
        #expect(found.map(\.status) == [.ready, .duplicate])
    }
}
