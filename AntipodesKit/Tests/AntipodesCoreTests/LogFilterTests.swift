import AntipodesCore
import Foundation
import Testing

@Suite("Filtering the log for the stats screen")
struct LogFilterTests {
    static let oslo = PlaceReference(
        id: .custom(UUID()),
        kind: .custom,
        name: "Oslo",
        countryCode: "NO"
    )
    static let bergen = PlaceReference(
        id: .custom(UUID()),
        kind: .custom,
        name: "Bergen",
        countryCode: "NO"
    )

    static func day(_ iso: String) -> FlexibleDate {
        .day(CalendarDate(iso: iso)!)
    }

    /// A 2023 trip with a visit and a journey of a train and a flight; a 2024 commute
    /// by train on no trip; and an undated visit.
    static func log() -> (TravelLog, Trip) {
        let trip = Trip(name: "Fjords")
        let log = TravelLog(
            trips: [trip],
            visits: [
                Visit(place: oslo, date: day("2023-06-01"), tripID: trip.id),
                Visit(place: bergen),
            ],
            journeys: [
                Journey(legs: [
                    JourneyLeg(
                        mode: .rail,
                        origin: oslo,
                        destination: bergen,
                        date: day("2023-06-02")
                    ),
                    JourneyLeg(
                        mode: .flight,
                        origin: bergen,
                        destination: oslo,
                        date: day("2023-06-05")
                    ),
                ], tripID: trip.id),
                Journey(legs: [
                    JourneyLeg(
                        mode: .rail,
                        origin: oslo,
                        destination: bergen,
                        date: day("2024-01-08"),
                        purpose: .commute
                    ),
                ]),
            ]
        )
        return (log, trip)
    }

    @Test("No filter is the whole log")
    func none() {
        let (log, _) = Self.log()
        #expect(log.restricted(to: .none) == log)
        #expect(!LogFilter.none.isActive)
    }

    @Test("A year keeps that year's visits and legs")
    func year() {
        let (log, _) = Self.log()
        let slice = log.restricted(to: LogFilter(year: 2023))
        #expect(slice.visits.count == 1)
        #expect(slice.allLegs.count == 2)
    }

    @Test("A trip keeps its own visits and journeys")
    func trip() {
        let (log, trip) = Self.log()
        let slice = log.restricted(to: LogFilter(tripID: trip.id))
        #expect(slice.visits.count == 1)
        #expect(slice.journeys.count == 1)
        #expect(slice.trips == log.trips)
    }

    /// Rail keeps the two train legs — splitting the 2023 journey — and no visits.
    @Test("A mode keeps only its legs, splitting journeys, and no visits")
    func mode() {
        let (log, _) = Self.log()
        let slice = log.restricted(to: LogFilter(mode: .rail))
        #expect(slice.visits.isEmpty)
        #expect(slice.allLegs.count == 2)
        #expect(slice.allLegs.allSatisfy { $0.mode == .rail })
        #expect(slice.journeys.count == 2)
    }

    @Test("Asking for commutes counts them, whatever the rule")
    func commute() {
        let (log, _) = Self.log()
        let filter = LogFilter(purpose: .commute)
        #expect(log.restricted(to: filter).allLegs.count == 1)
        #expect(filter.rules(from: .default).includeCommutes)
        #expect(!LogFilter(mode: .rail).rules(from: .default).includeCommutes)
    }
}
