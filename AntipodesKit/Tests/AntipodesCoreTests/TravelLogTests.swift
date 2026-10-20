import AntipodesCore
import Foundation
import Testing

@Suite("Travel log")
struct TravelLogTests {
    static let oslo = PlaceReference(
        id: .database(.city, 3_143_244),
        kind: .city,
        name: "Oslo",
        countryCode: "NO"
    )
    static let bergen = PlaceReference(
        id: .database(.city, 3_161_732),
        kind: .city,
        name: "Bergen",
        countryCode: "NO"
    )

    /// A backup restored on two devices before they synced leaves every record twice,
    /// with the same identity. Read back, each must appear once — or every total doubles.
    @Test("Records held more than once are read back once, keeping the first copy")
    func deduplicated() {
        let tripID = UUID()
        let visitID = UUID()
        let journeyID = UUID()
        let legID = UUID()
        let wishID = UUID()

        let trip = Trip(id: tripID, name: "Norway")
        let visit = Visit(id: visitID, place: Self.oslo, notes: "first")
        let visitCopy = Visit(id: visitID, place: Self.oslo, notes: "second")
        let leg = JourneyLeg(id: legID, mode: .rail, origin: Self.oslo, destination: Self.bergen)
        let journey = Journey(id: journeyID, legs: [leg, leg])
        let wish = WishlistItem(id: wishID, place: Self.bergen)
        let other = Visit(place: Self.bergen)

        let log = TravelLog(
            trips: [trip, trip],
            visits: [visit, other, visitCopy],
            journeys: [journey, journey],
            wishlist: [wish, wish]
        ).deduplicated()

        #expect(log.trips.map(\.id) == [tripID])
        // Order is kept, and of two copies the first wins.
        #expect(log.visits.map(\.id) == [visitID, other.id])
        #expect(log.visits.first?.notes == "first")
        #expect(log.journeys.count == 1)
        #expect(log.journeys.first?.legs.map(\.id) == [legID])
        #expect(log.wishlist.map(\.id) == [wishID])
    }

    @Test("A log with nothing duplicated is unchanged")
    func untouched() {
        let log = TravelLog(
            trips: [Trip(name: "A"), Trip(name: "B")],
            visits: [Visit(place: Self.oslo), Visit(place: Self.oslo)]
        )
        #expect(log.deduplicated() == log)
        #expect(TravelLog.empty.deduplicated() == .empty)
    }
}
