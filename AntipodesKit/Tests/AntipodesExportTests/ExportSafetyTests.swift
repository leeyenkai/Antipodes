import AntipodesCore
@testable import AntipodesExport
import Foundation
import Testing

@Suite("Export safety and fidelity")
struct ExportSafetyTests {
    /// A note carried in from another app's file can be a spreadsheet formula. Opened
    /// in Excel it would run; with an apostrophe in front it is text.
    @Test("Text that a spreadsheet would run as a formula is defused")
    func csvInjection() {
        var writer = CSVWriter(header: ["notes", "longitude"], numericColumns: ["longitude"])
        writer.append(["=HYPERLINK(\"http://x\")", "-73.7781"])
        writer.append(["@SUM(A1)", "10.75"])
        writer.append(["+1 bag", "-0.45"])
        writer.append(["Ordinary note", "0"])
        let lines = writer.encoded().components(separatedBy: "\r\n")
        #expect(lines[1] == "\"'=HYPERLINK(\"\"http://x\"\")\",-73.7781")
        #expect(lines[2] == "'@SUM(A1),10.75")
        // A negative longitude is a number, not a formula, and keeps its sign.
        #expect(lines[3] == "'+1 bag,-0.45")
        #expect(lines[4] == "Ordinary note,0")
    }

    @Test("Legs export the airport's own code, with the internal id in its own column")
    func airportCodes() throws {
        let osl = PlaceReference(
            id: .database(.airport, 2434),
            kind: .airport,
            name: "Oslo",
            code: "OSL"
        )
        let jfk = PlaceReference(
            id: .database(.airport, 3622),
            kind: .airport,
            name: "JFK",
            code: "JFK"
        )
        let flight = JourneyLeg(mode: .flight, origin: osl, destination: jfk)
        let log = TravelLog(journeys: [Journey(legs: [flight])])
        let data = try #require(TravelLogExport.csvFiles(for: log)["legs.csv"])
        let text = try #require(String(data: data, encoding: .utf8))
        let rows = text.components(separatedBy: "\r\n").map { $0.components(separatedBy: ",") }
        let header = rows[0]
        let row = rows[1]
        let value = { (name: String) in try #require(header.firstIndex(of: name)).map { row[$0] } }
        #expect(try value("from_code") == "OSL")
        #expect(try value("to_code") == "JFK")
        #expect(try value("from_place_id") == osl.id.description)
    }

    // One literal holding every field there is.
    // swiftlint:disable function_body_length
    /// Everything a backup can hold, so a restore that drops any field fails here.
    static func everything() throws -> TravelLog {
        let trip = Trip(
            name: "Everything",
            notes: "All fields",
            createdAt: Date(timeIntervalSinceReferenceDate: 750_000_000)
        )
        let pin = PlaceReference(
            id: .custom(UUID()), kind: .custom, name: "Hut on the ridge",
            coordinate: Coordinate(latitude: 61.5, longitude: 8.25),
            countryCode: "NO", countryName: "Norway", continent: .europe,
            regionCode: "NO.34", regionName: "Innlandet", timeZoneIdentifier: "Europe/Oslo"
        )
        let oslo = PlaceReference(
            id: .database(.airport, 2434), kind: .airport, name: "Oslo Gardermoen",
            coordinate: Coordinate(latitude: 60.1939, longitude: 11.1004),
            countryCode: "NO", countryName: "Norway", continent: .europe,
            cityID: 3_143_244, cityName: "Oslo", timeZoneIdentifier: "Europe/Oslo", code: "OSL"
        )
        let bergen = PlaceReference(
            id: .database(.city, 3_161_732),
            kind: .city,
            name: "Bergen",
            countryCode: "NO"
        )
        let stay = try FlexibleDate.span(
            #require(CalendarDate(iso: "2024-12-28")),
            #require(CalendarDate(iso: "2025-01-03"))
        )
        let leg = try JourneyLeg(
            mode: .rail, origin: oslo, destination: bergen,
            date: .day(#require(CalendarDate(iso: "2024-06-12"))),
            purpose: .work, storedPathLengthKm: 496, distanceKmOverride: 497.5,
            durationMinutesOverride: 410,
            times: LegTimes(
                scheduledDeparture: LocalDateTime(iso: "2024-06-12T08:25"),
                scheduledArrival: LocalDateTime(iso: "2024-06-12T15:20"),
                actualDeparture: LocalDateTime(iso: "2024-06-12T08:31"),
                actualArrival: LocalDateTime(iso: "2024-06-12T15:42")
            ),
            missedConnection: true, routeID: 1, routeName: "Bergen Line", operatorName: "Vy",
            serviceNumber: "R 61", vehicle: "Class 73", registration: "73 001",
            travelClass: "Komfort", seat: "Car 2, 41", rating: 5, notes: "Snow at Finse"
        )
        return TravelLog(
            trips: [trip],
            visits: [
                Visit(
                    place: pin,
                    visitType: .dayTrip,
                    date: stay,
                    tripID: trip.id,
                    rating: 4,
                    notes: "=not a formula in JSON",
                    createdAt: Date(timeIntervalSinceReferenceDate: 750_000_100)
                ),
                Visit(place: bergen, visitType: .passedThrough, date: .month(year: 2023, month: 7)),
            ],
            journeys: [Journey(legs: [leg], tripID: trip.id, title: "To Bergen")],
            wishlist: [
                WishlistItem(
                    place: bergen,
                    routeID: 1,
                    routeName: "Bergen Line",
                    notes: "Again",
                    createdAt: Date(timeIntervalSinceReferenceDate: 750_000_200)
                ),
                WishlistItem(place: pin),
            ]
        )
    }

    // swiftlint:enable function_body_length

    @Test("A JSON backup restores every field exactly")
    func fullRoundTrip() throws {
        let original = try Self.everything()
        let restored = try TravelLogExport.importLog(fromJSON: TravelLogExport.json(for: original))
        #expect(restored == original)
    }

    @Test("A backup from a newer version is refused, and a stranger file named as such")
    func refusals() throws {
        let newer = Data(
            #"{"formatVersion": 99, "application": "Antipodes", "exportedAt": "", "log": {}}"#
                .utf8
        )
        #expect(throws: TravelLogExport.ImportFailure.newerVersion(99)) {
            try TravelLogExport.importLog(fromJSON: newer)
        }
        #expect(throws: TravelLogExport.ImportFailure.notABackup) {
            try TravelLogExport.importLog(fromJSON: Data("date,from,to\n".utf8))
        }
        #expect(throws: TravelLogExport.ImportFailure.notABackup) {
            try TravelLogExport.importLog(fromJSON: Data(#"{"formatVersion": 2, "log": 7}"#.utf8))
        }
    }
}
