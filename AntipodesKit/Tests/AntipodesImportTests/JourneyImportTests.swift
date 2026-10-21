import AntipodesCore
@testable import AntipodesImport
import Foundation
import Testing

/// Rail logs and other journey lists (R-JLOG-7, R-LOG-8): a mode per row, stations
/// matched by name, a stated distance kept, and JSON read as well as CSV.
@Suite("Importing journeys of every mode")
struct JourneyImportTests {
    static func city(_ name: String) -> PlaceReference {
        PlaceReference(id: .custom(UUID()), kind: .city, name: name, countryCode: "NO")
    }

    static let places = ["oslo": city("Oslo"), "bergen": city("Bergen"), "flåm": city("Flåm")]

    static func candidates(
        _ data: String,
        defaultMode: TravelMode = .flight,
        existing: [JourneyLeg] = []
    ) async throws -> [FlightImportCandidate] {
        let (_, rows) = try FlightLogImport.parse(
            Data(data.utf8),
            dayFirst: true,
            defaultMode: defaultMode
        )
        return await FlightLogImport.match(
            rows,
            existing: existing,
            airport: { _ in nil },
            place: { name, _ in places[name.lowercased()] }
        )
    }

    /// A rail log with a mode column, station names and the distance along the track.
    @Test("A rail log's modes, stations and distances are read")
    func railLog() async throws {
        let csv = """
        Date,Mode,From station,To station,Operator,Train,Distance (km)
        2024-06-12,Train,Oslo,Bergen,Vy,R62,496
        2024-06-14,Ferry,Bergen,Flåm,Norled,,"181.5"
        """
        let found = try await Self.candidates(csv)
        #expect(found.map(\.status) == [.ready, .ready])
        let train = try #require(found.first?.leg)
        #expect(train.mode == .rail)
        #expect(train.distanceKm == 496)
        #expect(train.operatorName == "Vy")
        #expect(train.serviceNumber == "R62")
        #expect(found.last?.leg?.mode == .ferry)
        #expect(found.last?.leg?.distanceKm == 181.5)
    }

    /// No mode column: the user says what the list is of.
    @Test("A list with no mode column takes the mode it is read as")
    func defaultMode() async throws {
        let csv = "date,from,to\n2024-06-12,Oslo,Bergen\n"
        let asTrains = try await Self.candidates(csv, defaultMode: .rail)
        #expect(asTrains.first?.leg?.mode == .rail)
        // Read as flights, "Oslo" is not an airport code, so the row waits for a choice.
        let asFlights = try await Self.candidates(csv)
        #expect(asFlights.first?.status == .needsAirport)
    }

    @Test("A mode the importer does not know is flagged, not guessed silently")
    func unknownMode() throws {
        let csv = "date,mode,from,to\n2024-06-12,hovercraft,Oslo,Bergen\n"
        let (_, rows) = try FlightLogImport.parse(
            Data(csv.utf8),
            dayFirst: true,
            defaultMode: .rail
        )
        #expect(rows.first?.mode == .rail)
        #expect(rows.first?.problems.isEmpty == false)
    }

    /// A JSON export, as an object holding its list, with a number for the distance and
    /// miles named in the key.
    @Test("A JSON journey list reads like a CSV one")
    func json() async throws {
        let json = """
        {"exported": "2024-07-01", "journeys": [
          {"date": "2024-06-12", "mode": "rail", "from": "Oslo", "to": "Bergen", "miles": 308.2}
        ]}
        """
        let (format, rows) = try FlightLogImport.parse(Data(json.utf8), dayFirst: true)
        #expect(format == .json)
        #expect(rows.count == 1)
        // 308.2 mi × 1.609344 = 496.0 km.
        #expect(abs((rows.first?.distanceKm ?? 0) - 496.0) < 0.1)
        let found = try await Self.candidates(json)
        #expect(found.first?.leg?.mode == .rail)
    }

    /// The same train on the same day is a duplicate; the same route by ferry is not.
    @Test("Duplicates are matched by mode as well as day and route")
    func duplicatesByMode() async throws {
        let existing = try JourneyLeg(
            mode: .rail,
            origin: #require(Self.places["oslo"]),
            destination: #require(Self.places["bergen"]),
            date: .day(#require(CalendarDate(iso: "2024-06-12")))
        )
        let csv = """
        date,mode,from,to
        2024-06-12,train,Oslo,Bergen
        2024-06-12,ferry,Oslo,Bergen
        """
        let found = try await Self.candidates(csv, existing: [existing])
        #expect(found.map(\.status) == [.duplicate, .ready])
    }

    @Test("Everyday words for modes are understood")
    func modeWords() {
        #expect(TravelMode(importText: "Train") == .rail)
        #expect(TravelMode(importText: "metro") == .cityTransit)
        #expect(TravelMode(importText: "Bus") == .coach)
        #expect(TravelMode(importText: "gondola") == .cableAndMountain)
        #expect(TravelMode(importText: "bike") == .humanPowered)
        #expect(TravelMode(importText: "roadTrip") == .roadTrip)
        #expect(TravelMode(importText: "teleport") == nil)
    }
}
