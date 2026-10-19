import AntipodesCore
@testable import AntipodesImport
import Foundation
import Testing

@Suite("CSV reading")
struct CSVReaderTests {
    @Test("Quoted fields keep their commas, quotes and line breaks")
    func quoting() throws {
        let rows = try CSVReader
            .rows(
                from: "a,b\r\n\"Washington, D.C.\",\"He said \"\"hi\"\"\"\r\n\"two\nlines\",x\r\n"
            )
        #expect(rows == [["a", "b"], ["Washington, D.C.", "He said \"hi\""], ["two\nlines", "x"]])
    }

    @Test("A byte-order mark is dropped and LF endings work as well as CRLF")
    func bomAndLineEndings() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("a,b\n1,2\n".utf8)
        #expect(try CSVReader.rows(from: data) == [["a", "b"], ["1", "2"]])
    }

    @Test("Semicolon-separated files are recognised from the header")
    func semicolons() throws {
        #expect(try CSVReader.rows(from: "date;from;to\n2024-01-01;OSL;JFK") == [
            ["date", "from", "to"], ["2024-01-01", "OSL", "JFK"],
        ])
    }

    @Test("A quote that never closes is an error, not a silently swallowed file")
    func unterminated() {
        #expect(throws: CSVReader.Failure.unterminatedQuote(line: 2)) {
            try CSVReader.rows(from: "a,b\n\"never closed,1\n2,3")
        }
    }

    @Test("Columns are found by name however the header spells them")
    func columnNames() throws {
        let table = try CSVTable(data: Data("Date,Flight Number,flight_class\n".utf8))
        #expect(table.column(["flightnumber"]) == 1)
        #expect(table.column(["flightclass"]) == 2)
        #expect(table.column(["nothing"]) == nil)
    }
}

@Suite("Airport codes")
struct AirportCodeTests {
    @Test("Codes are found however an export writes the airport")
    func extraction() {
        #expect(AirportCode.extract(from: "OSL") == "OSL")
        #expect(AirportCode.extract(from: "engm") == nil) // lowercase four letters is a word
        #expect(AirportCode.extract(from: "ENGM") == "ENGM")
        #expect(AirportCode.extract(from: "Oslo / Oslo Gardermoen (OSL/ENGM)") == "OSL")
        #expect(AirportCode.extract(from: "Somewhere (ENGM)") == "ENGM")
        #expect(AirportCode.extract(from: "JFK - New York") == "JFK")
        #expect(AirportCode.extract(from: "New York") == nil)
    }
}

@Suite("Flight log import")
struct FlightLogImportTests {
    static let myFlightradar24 = """
    Date,Flight number,From,To,Dep time,Arr time,Duration,Airline,Aircraft,Registration,\
    Seat number,Seat type,Flight class,Flight reason,Note,Dep_id,Arr_id,Airline_id,Aircraft_id
    2019-06-12,SK903,Oslo / Oslo Gardermoen (OSL/ENGM),New York / John F. Kennedy (JFK/KJFK),\
    09:00:00,11:30:00,08:30:00,SAS (SK/SAS),Airbus A330-300 (A333),LN-RKH,23A,1,2,2,\
    "Window, nice",1,2,3,4
    2019-06-20,SK904,JFK,OSL,17:45:00,07:40:00,07:55:00,SAS,,,,,,,,,,,
    """

    @Test("myFlightradar24 is recognised and every field lands where it belongs")
    func myFlightradar24() throws {
        let (format, rows) = try FlightLogImport.parse(
            Data(Self.myFlightradar24.utf8),
            dayFirst: true
        )
        #expect(format == .myFlightradar24)
        #expect(rows.count == 2)
        let first = try #require(rows.first)
        #expect(first.line == 2)
        #expect(try first.date == .day(#require(CalendarDate(year: 2019, month: 6, day: 12))))
        #expect(first.originCode == "OSL")
        #expect(first.destinationCode == "JFK")
        #expect(first.flightNumber == "SK903")
        #expect(first.registration == "LN-RKH")
        #expect(first.travelClass == "Business") // class 2
        #expect(first.purpose == .work) // reason 2
        #expect(first.notes == "Window, nice")
        #expect(first.times.scheduledDeparture?.iso == "2019-06-12T09:00")
        #expect(first.problems.isEmpty)
    }

    @Test("A day-first file is detected from its own dates")
    func dayFirst() throws {
        let csv = "date,from,to\n03/04/2021,OSL,BGO\n25/12/2021,BGO,OSL\n"
        let (_, rows) = try FlightLogImport.parse(Data(csv.utf8), dayFirst: false)
        #expect(try rows.first?.date == .day(#require(CalendarDate(year: 2021, month: 4, day: 3))))
        let american = "date,from,to\n03/04/2021,OSL,BGO\n12/25/2021,BGO,OSL\n"
        let (_, usRows) = try FlightLogImport.parse(Data(american.utf8), dayFirst: true)
        #expect(try usRows.first?.date == .day(#require(CalendarDate(
            year: 2021,
            month: 3,
            day: 4
        ))))
    }

    @Test("A file that is not a flight list says which column it lacks")
    func notAFlightList() {
        #expect(throws: FlightLogImport.Failure.missingColumns(["from", "to"])) {
            try FlightLogImport.parse(Data("date,place\n2024-01-01,Oslo\n".utf8), dayFirst: true)
        }
    }

    static func airport(_ code: String, zone: String) -> PlaceReference {
        PlaceReference(
            id: .database(
                .airport,
                Int64(code.unicodeScalars.reduce(0) { $0 * 31 + Int($1.value) })
            ),
            kind: .airport,
            name: code,
            coordinate: Coordinate(latitude: 0, longitude: 0),
            timeZoneIdentifier: zone,
            code: code
        )
    }

    /// The return flight leaves New York at 17:45 and lands in Oslo at 07:40 — on the
    /// wall clock, "before" it left. Read in the two zones that is −4 h 05 m, so the
    /// only sensible reading is the next morning: 17:45−4 = 21:45Z to 07:40+2 = 05:40Z
    /// the next day, 7 h 55 m = 475 minutes, which is the duration the file gives.
    @Test("Airports are matched by code, an overnight arrival moves to the next day")
    func matching() async throws {
        let (_, rows) = try FlightLogImport.parse(Data(Self.myFlightradar24.utf8), dayFirst: true)
        let airports = [
            "OSL": Self.airport("OSL", zone: "Europe/Oslo"),
            "JFK": Self.airport("JFK", zone: "America/New_York"),
        ]
        let candidates = await FlightLogImport.match(rows, existing: []) { airports[$0] }
        #expect(candidates.allSatisfy { $0.status == .ready })
        let back = try #require(candidates.last?.leg)
        #expect(back.times.scheduledArrival?.iso == "2019-06-21T07:40")
        #expect(back.durationMinutes == 475)
    }

    @Test("A flight already in the log is flagged and left out by default")
    func duplicates() async throws {
        let (_, rows) = try FlightLogImport.parse(Data(Self.myFlightradar24.utf8), dayFirst: true)
        let osl = Self.airport("OSL", zone: "Europe/Oslo")
        let jfk = Self.airport("JFK", zone: "America/New_York")
        let existing = try JourneyLeg(
            mode: .flight,
            origin: osl,
            destination: jfk,
            date: .day(#require(CalendarDate(year: 2019, month: 6, day: 12))),
            serviceNumber: "SK 903"
        )
        let candidates = await FlightLogImport.match(rows, existing: [existing]) { [
            "OSL": osl,
            "JFK": jfk,
        ][$0] }
        #expect(candidates.first?.status == .duplicate)
        #expect(candidates.first?.include == false)
        #expect(candidates.last?.status == .ready)
    }

    @Test("An airport the database does not know leaves the row for review")
    func unmatched() async throws {
        let (_, rows) = try FlightLogImport.parse(
            Data("date,from,to\n2024-01-01,OSL,ZZZ\n".utf8),
            dayFirst: true
        )
        let candidates = await FlightLogImport.match(rows, existing: []) { code in
            code == "OSL" ? Self.airport("OSL", zone: "Europe/Oslo") : nil
        }
        #expect(candidates.first?.status == .needsAirport)
        #expect(candidates.first?.include == false)
        #expect(candidates.first?.leg == nil)
    }
}

@Suite("Photo clustering")
struct PhotoClusteringTests {
    static func place(_ name: String, id: Int64) -> PlaceReference {
        PlaceReference(
            id: .database(.city, id),
            kind: .city,
            name: name,
            coordinate: Coordinate(latitude: 0, longitude: 0),
            timeZoneIdentifier: "UTC"
        )
    }

    static let paris = place("Paris", id: 1)
    static let rome = place("Rome", id: 2)
    static let home = place("Home", id: 3)

    static func photo(_ place: PlaceReference, _ iso: String) -> LocatedPhoto {
        let day = CalendarDate(iso: iso)!
        return LocatedPhoto(
            sample: PhotoSample(
                taken: day.date()!.addingTimeInterval(12 * 3600),
                coordinate: place.coordinate!
            ),
            place: place
        )
    }

    /// Paris on the 1st, 2nd and 4th (one gap day) is one stay, 1–4 June. Paris again on
    /// the 20th is a second stay. Rome on the 10th is a day trip. Home is left out.
    @Test("Photos become stays, split by gaps and with home left out")
    func clustering() {
        let photos = [
            Self.photo(Self.paris, "2024-06-01"), Self.photo(Self.paris, "2024-06-02"),
            Self.photo(Self.paris, "2024-06-04"), Self.photo(Self.rome, "2024-06-10"),
            Self.photo(Self.paris, "2024-06-20"), Self.photo(Self.home, "2024-06-15"),
        ]
        let suggestions = PhotoClustering.suggest(photos, home: Self.home)
        #expect(suggestions.count == 3)
        let firstParis = suggestions.first { $0.place.name == "Paris" && $0.start.day == 1 }
        #expect(firstParis?.end.day == 4)
        #expect(firstParis?.photoCount == 3)
        #expect(firstParis?.suggestedType == .stayed)
        #expect(suggestions.first { $0.place.name == "Rome" }?.suggestedType == .dayTrip)
        #expect(!suggestions.contains { $0.place.name == "Home" })
    }

    @Test("A suggestion overlapping a logged visit is marked as already logged")
    func alreadyLogged() throws {
        let logged = try Visit(
            place: Self.rome,
            date: .span(
                #require(CalendarDate(year: 2024, month: 6, day: 9)),
                #require(CalendarDate(year: 2024, month: 6, day: 11))
            )
        )
        let suggestions = PhotoClustering.suggest(
            [Self.photo(Self.rome, "2024-06-10")],
            existing: [logged]
        )
        #expect(suggestions.first?.alreadyLogged == true)
    }
}
