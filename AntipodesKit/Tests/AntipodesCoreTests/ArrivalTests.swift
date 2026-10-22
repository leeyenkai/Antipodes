import AntipodesCore
import Foundation
import Testing

/// Which journeys arrive somewhere, for logging the arrival as a visit (D-32).
@Suite("Arrivals")
struct ArrivalTests {
    static func airport(_ code: String, _ id: Int64, _ country: String) -> PlaceReference {
        PlaceReference(
            id: .database(.airport, id),
            kind: .airport,
            name: code,
            countryCode: country
        )
    }

    static func city(_ name: String, _ id: Int64, _ country: String) -> PlaceReference {
        PlaceReference(id: .database(.city, id), kind: .city, name: name, countryCode: country)
    }

    static let osl = airport("OSL", 1, "NO")
    static let hel = airport("HEL", 2, "FI")
    static let hnd = airport("HND", 3, "JP")
    static let oslo = city("Oslo", 3_143_244, "NO")
    static let tokyo = city("Tokyo", 1_850_147, "JP")
    static let kyoto = city("Kyoto", 1_857_910, "JP")

    static func day(_ iso: String) -> FlexibleDate {
        CalendarDate(iso: iso).map(FlexibleDate.day) ?? .unknown
    }

    static func leg(
        _ mode: TravelMode,
        _ from: PlaceReference,
        _ to: PlaceReference,
        _ date: String
    ) -> JourneyLeg {
        JourneyLeg(mode: mode, origin: from, destination: to, date: day(date))
    }

    /// OSL → HEL and HEL → HND on 1 April is one run of connections: it arrives in
    /// Tokyo, not Helsinki. HND → OSL on 11 April is an arrival of its own.
    @Test("A connection is not an arrival; the end of the run is")
    func connections() {
        let legs = [
            Self.leg(.flight, Self.hnd, Self.osl, "2024-04-11"),
            Self.leg(.flight, Self.osl, Self.hel, "2024-04-01"),
            Self.leg(.flight, Self.hel, Self.hnd, "2024-04-01"),
        ]
        let finals = Arrivals.finalLegs(of: legs)
        #expect(finals.map(\.destination.name) == ["HND", "OSL"])
    }

    /// A connection can leave the day after landing — an overnight wait — but a flight
    /// two days later starts a new journey.
    @Test("A connection leaves the same day or the next")
    func connectionWindow() {
        let nextDay = [
            Self.leg(.flight, Self.osl, Self.hel, "2024-04-01"),
            Self.leg(.flight, Self.hel, Self.hnd, "2024-04-02"),
        ]
        #expect(Arrivals.finalLegs(of: nextDay).map(\.destination.name) == ["HND"])
        let twoDaysLater = [
            Self.leg(.flight, Self.osl, Self.hel, "2024-04-01"),
            Self.leg(.flight, Self.hel, Self.hnd, "2024-04-03"),
        ]
        #expect(Arrivals.finalLegs(of: twoDaysLater).map(\.destination.name) == ["HEL", "HND"])
    }

    @Test("A city transit ride or a cable car does not arrive anywhere new")
    func ridesWithinAPlace() {
        let ride = Self.leg(.cityTransit, Self.tokyo, Self.kyoto, "2024-04-05")
        let gondola = Self.leg(.cableAndMountain, Self.tokyo, Self.kyoto, "2024-04-05")
        #expect(Arrivals.finalLegs(of: [ride, gondola]).isEmpty)
    }

    /// Departing at 22:00 on 1 April and landing at 07:00 on 2 April arrives on the 2nd.
    @Test("An overnight leg arrives on the day it lands")
    func overnightArrival() throws {
        var flight = Self.leg(.flight, Self.osl, Self.hnd, "2024-04-01")
        let landing = try #require(CalendarDate(iso: "2024-04-02"))
        flight.times.scheduledArrival = LocalDateTime(date: landing, hour: 7, minute: 0)
        #expect(Arrivals.arrivalDate(of: flight) == .day(landing))
    }

    @Test("Coming home is not a visit")
    func home() {
        #expect(!Arrivals.shouldLog(
            Self.oslo,
            on: Self.day("2024-04-11"),
            home: Self.oslo,
            existing: []
        ))
        #expect(Arrivals.shouldLog(
            Self.tokyo,
            on: Self.day("2024-04-01"),
            home: Self.oslo,
            existing: []
        ))
    }

    /// Tokyo logged as a stay from 1 to 6 April already covers an arrival on the 1st; a
    /// second trip in May is a new visit.
    @Test("An arrival where a visit already covers the day is not logged twice")
    func duplicates() throws {
        let start = try #require(CalendarDate(iso: "2024-04-01"))
        let end = try #require(CalendarDate(iso: "2024-04-06"))
        let stay = Visit(place: Self.tokyo, date: .span(start, end))
        #expect(!Arrivals.shouldLog(
            Self.tokyo,
            on: Self.day("2024-04-01"),
            home: nil,
            existing: [stay]
        ))
        #expect(Arrivals.shouldLog(
            Self.tokyo,
            on: Self.day("2024-05-10"),
            home: nil,
            existing: [stay]
        ))
        // An undated arrival is logged only where there is no visit at all.
        #expect(!Arrivals.shouldLog(Self.tokyo, on: .unknown, home: nil, existing: [stay]))
    }

    @Test("Two arrivals at the same place on the same day make one visit")
    func arrivalsDeduplicated() {
        let planned = Arrivals.visits(
            arrivingAt: [
                (Self.tokyo, Self.day("2024-04-01")),
                (Self.tokyo, Self.day("2024-04-01")),
                (Self.kyoto, Self.day("2024-04-07")),
            ],
            home: Self.oslo,
            existing: []
        )
        #expect(planned.map(\.place.name) == ["Tokyo", "Kyoto"])
    }
}
