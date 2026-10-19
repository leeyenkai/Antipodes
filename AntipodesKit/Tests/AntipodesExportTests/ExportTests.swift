import AntipodesCore
@testable import AntipodesExport
import Foundation
import Testing

@Suite("CSV writing")
struct CSVWriterTests {
    /// Place names really do contain commas, quotes and apostrophes
    /// ("Washington, D.C.", "L'Anse aux Meadows"), so quoting is load-bearing.
    @Test("Quotes only the fields that need it")
    func quoting() {
        #expect(CSVWriter.field("Oslo") == "Oslo")
        #expect(CSVWriter.field("Washington, D.C.") == "\"Washington, D.C.\"")
        #expect(CSVWriter.field("He said \"hi\"") == "\"He said \"\"hi\"\"\"")
        #expect(CSVWriter.field("line\nbreak") == "\"line\nbreak\"")
        #expect(CSVWriter.field(" padded ") == "\" padded \"")
        // swiftlint:disable:next empty_string - the empty field IS what is asserted
        #expect(CSVWriter.field("") == "")
    }

    @Test("Rows are CRLF-terminated as RFC 4180 requires")
    func lineEndings() {
        var writer = CSVWriter(header: ["a", "b"])
        writer.append(["1", "2"])
        #expect(writer.encoded() == "a,b\r\n1,2\r\n")
    }

    @Test("A nil value becomes an empty field, not the text \"nil\"")
    func nilHandling() {
        var writer = CSVWriter(header: ["a", "b"])
        writer.append(["1", nil])
        #expect(writer.encoded() == "a,b\r\n1,\r\n")
    }
}

@Suite("Travel log export")
struct TravelLogExportTests {
    // One fixture covering every exported column.
    // swiftlint:disable function_body_length
    static func sampleLog() -> TravelLog {
        let trip = Trip(name: "Nordics 2024")
        let oslo = PlaceReference(
            id: .database(.city, 10),
            kind: .city,
            name: "Oslo",
            coordinate: Coordinate(latitude: 59.9139, longitude: 10.7522),
            countryCode: "NO",
            countryName: "Norway",
            continent: .europe,
            regionCode: "NO-03",
            cityID: 10,
            cityName: "Oslo"
        )
        let osl = PlaceReference(
            id: .database(.airport, 1),
            kind: .airport,
            name: "Oslo Gardermoen",
            coordinate: Coordinate(latitude: 60.1939, longitude: 11.1004),
            countryCode: "NO",
            countryName: "Norway",
            continent: .europe
        )
        let jfk = PlaceReference(
            id: .database(.airport, 2),
            kind: .airport,
            name: "New York John F. Kennedy",
            coordinate: Coordinate(latitude: 40.6413, longitude: -73.7781),
            countryCode: "US",
            countryName: "United States",
            continent: .northAmerica
        )

        let flight = JourneyLeg(
            mode: .flight,
            origin: osl,
            destination: jfk,
            date: .day(CalendarDate(iso: "2024-06-20")!),
            times: LegTimes(scheduledDeparture: LocalDateTime(iso: "2024-06-20T09:00")),
            operatorName: "SK",
            serviceNumber: "SK905",
            registration: "LN-RKH"
        )
        let rome = PlaceReference(
            id: .database(.city, 3_169_070),
            kind: .city,
            name: "Rome",
            countryCode: "IT",
            countryName: "Italy"
        )

        return TravelLog(
            trips: [trip],
            visits: [
                Visit(
                    place: oslo,
                    visitType: .stayed,
                    date: .day(CalendarDate(iso: "2024-06-12")!),
                    tripID: trip.id,
                    rating: 5,
                    notes: "Rainy, but good coffee"
                ),
            ],
            journeys: [
                Journey(legs: [flight], tripID: trip.id),
            ],
            wishlist: [WishlistItem(place: rome, notes: "Spring")]
        )
    }

    // swiftlint:enable function_body_length

    /// R-LOG-9, R-PRIV-6 and M1 acceptance criterion 9: the export is the user's way
    /// out of a no-account app, so it must contain everything.
    @Test("CSV export produces one file per entity, each with its rows")
    func csvFiles() throws {
        let files = TravelLogExport.csvFiles(for: Self.sampleLog())
        #expect(Set(files.keys) == [
            "trips.csv",
            "visits.csv",
            "journeys.csv",
            "legs.csv",
            "wishlist.csv",
        ])

        let visitsData = try #require(files["visits.csv"])
        let visits = try #require(String(data: visitsData, encoding: .utf8))
        #expect(visits.contains("Oslo"))
        #expect(visits.contains("2024-06-12"))
        #expect(visits.contains("stayed"))
        #expect(visits.contains("NO"))
        // A note containing a comma must come back quoted, or the file is unparseable.
        #expect(visits.contains("\"Rainy, but good coffee\""))

        let legsData = try #require(files["legs.csv"])
        let legs = try #require(String(data: legsData, encoding: .utf8))
        #expect(legs.contains("flight"))
        #expect(legs.contains("SK905"))
        #expect(legs.contains("greatCircleExact"))
        #expect(legs.contains("2024-06-20T09:00"))
        #expect(legs.contains("LN-RKH"))

        let wishlistData = try #require(files["wishlist.csv"])
        let wishlist = try #require(String(data: wishlistData, encoding: .utf8))
        #expect(wishlist.contains("Rome"))
    }

    @Test("Every CSV file has as many rows as records, plus a header")
    func csvRowCounts() throws {
        let files = TravelLogExport.csvFiles(for: Self.sampleLog())
        for (name, data) in files {
            let text = try #require(String(data: data, encoding: .utf8))
            let rows = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            #expect(rows.count == 2, "\(name) should hold a header and one record")
        }
    }

    @Test("JSON export round-trips the whole log")
    func jsonRoundTrip() throws {
        let original = Self.sampleLog()
        let data = try TravelLogExport.json(for: original)
        let restored = try TravelLogExport.importLog(fromJSON: data)

        #expect(restored.trips.count == original.trips.count)
        #expect(restored.visits.count == original.visits.count)
        #expect(restored.journeys.count == original.journeys.count)
        #expect(restored.visits.first?.place.name == "Oslo")
        #expect(restored.visits.first?.date == original.visits.first?.date)
        #expect(restored.visits.first?.notes == "Rainy, but good coffee")
        #expect(restored.journeys.first?.legs.first?.serviceNumber == "SK905")
        #expect(restored.journeys.first?.legs.first?.times.scheduledDeparture?
            .iso == "2024-06-20T09:00")
        #expect(restored.wishlist.first?.place?.name == "Rome")
        // The place reference must survive, or coverage stats break on re-import.
        #expect(restored.visits.first?.place.countryCode == "NO")
        #expect(restored.visits.first?.place.continent == .europe)
    }

    @Test("JSON export carries a format version")
    func formatVersion() throws {
        let data = try TravelLogExport.json(for: Self.sampleLog())
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"formatVersion\" : 2"))
        #expect(text.contains("\"application\" : \"Antipodes\""))
    }

    @Test("An empty log exports valid, empty files rather than failing")
    func emptyLog() throws {
        let files = TravelLogExport.csvFiles(for: .empty)
        for (_, data) in files {
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count == 1)
        }
        let restored = try TravelLogExport.importLog(
            fromJSON: TravelLogExport.json(for: .empty)
        )
        #expect(restored.isEmpty)
    }

    @Test("An unknown date exports as an empty field and comes back unknown")
    func unknownDates() throws {
        let place = PlaceReference(
            id: .database(.country, 1),
            kind: .country,
            name: "Norway",
            countryCode: "NO",
            countryName: "Norway",
            continent: .europe
        )
        let log = TravelLog(visits: [Visit(place: place, date: .unknown)])
        let restored = try TravelLogExport.importLog(
            fromJSON: TravelLogExport.json(for: log)
        )
        #expect(restored.visits.first?.date == .unknown)
    }
}
