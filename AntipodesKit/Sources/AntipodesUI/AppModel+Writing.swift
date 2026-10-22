import AntipodesCore
import AntipodesStore
import Foundation

/// Every change to the log goes through here: a write, a reload, and a failure turned
/// into the app-wide alert.
public extension AppModel {
    // MARK: - Writing

    /// Runs a write, reloads, and turns a failure into the app-wide alert.
    @discardableResult
    func perform(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func logVisit(
        place: PlaceReference,
        visitType: VisitType,
        date: FlexibleDate,
        tripID: UUID?,
        rating: Int? = nil,
        notes: String? = nil
    ) throws {
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logVisit(
            place: place,
            visitType: visitType,
            date: date,
            trip: trip,
            rating: rating,
            notes: notes?.trimmedOrNil
        )
        reload()
    }

    @discardableResult
    func updateVisit(_ visit: Visit) -> Bool {
        perform { try store.updateVisit(visit) }
    }

    /// Writes many edited visits in one save, reloading once at the end.
    func updateVisits(_ visits: [Visit]) {
        perform { try store.updateVisits(visits) }
    }

    func deleteVisits(_ ids: [UUID]) {
        let removed = log.visits.filter { ids.contains($0.id) }
        if perform({ try store.deleteVisits(ids) }) {
            offerUndo(Deletion(
                message: removed.count == 1
                    ? "Deleted \(removed[0].place.name)" : "Deleted \(removed.count) places",
                records: TravelLog(visits: removed)
            ))
        }
    }

    func moveVisits(_ ids: [UUID], toTrip tripID: UUID?) {
        perform { try store.moveVisits(ids, toTrip: tripID) }
    }

    /// Logs a journey and, where given, the places it arrived at as stays (D-32).
    func logJourney(
        legs: [JourneyLeg],
        tripID: UUID?,
        title: String? = nil,
        arrivals: [Arrival] = []
    ) throws {
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logJourney(
            legs: legs,
            trip: trip,
            title: title?.trimmedOrNil,
            arrivals: arrivals.map { (place: $0.place, visitType: .stayed, date: $0.date) }
        )
        reload()
    }

    @discardableResult
    func updateJourney(_ journey: Journey) -> Bool {
        perform { try store.updateJourney(journey) }
    }

    func deleteJourneys(_ ids: [UUID]) {
        let removed = log.journeys.filter { ids.contains($0.id) }
        if perform({ try store.deleteJourneys(ids) }) {
            offerUndo(Deletion(
                message: removed.count == 1
                    ? "Deleted \(removed[0].displayTitle)" : "Deleted \(removed.count) journeys",
                records: TravelLog(journeys: removed)
            ))
        }
    }

    func moveJourneys(_ ids: [UUID], toTrip tripID: UUID?) {
        perform { try store.moveJourneys(ids, toTrip: tripID) }
    }

    /// Duplicates a leg as a new journey dated today (R-JLOG-6).
    /// Logs the same ride again, dated today (R-JLOG-6). It joins the original's trip only
    /// while that trip is still under way — its last record no more than a week ago — so
    /// a holiday's second tram files with the holiday and a later commute does not.
    func rideAgain(_ leg: JourneyLeg, tripID: UUID?) {
        let today = CalendarDate.today()
        let ongoingTrip = tripID.flatMap { id in
            dates(ofTrip: id).flatMap { $0.end.days(to: today) <= 7 ? id : nil }
        }
        if perform({
            let trip = try ongoingTrip.flatMap { try store.trip(id: $0) }
            try store.logJourney(legs: [leg.rideAgain(on: .day(today))], trip: trip)
        }) {
            rideLoggedAgain += 1
        }
    }

    /// The alert for a trip that could not be made.
    static func tripNotCreated(_ error: any Error) -> String {
        "The trip couldn't be created. \(error.localizedDescription)"
    }

    @discardableResult
    func createTrip(name: String?, notes: String? = nil) throws -> Trip {
        let trip = try store.createTrip(name: name?.trimmedOrNil, notes: notes?.trimmedOrNil)
        reload()
        return trip.asTrip
    }

    @discardableResult
    func updateTrip(_ trip: Trip) -> Bool {
        perform { try store.updateTrip(trip) }
    }

    func deleteTrip(_ id: UUID, deletingContents: Bool) {
        guard let trip = log.trip(id: id) else { return }
        let contents = log.restricted(toTrip: id)
        let name = trip.name ?? "trip"
        if perform({ try store.deleteTrip(id: id, deletingContents: deletingContents) }) {
            offerUndo(Deletion(
                message: "Deleted \(name)",
                records: deletingContents ? contents : TravelLog(trips: [trip]),
                refile: deletingContents ? nil : (
                    trip: id,
                    visits: contents.visits.map(\.id),
                    journeys: contents.journeys.map(\.id)
                )
            ))
        }
    }

    /// Erases the log and everything personal kept beside it (R-PRIV-6).
    ///
    /// Home is the user's own location, so it goes too; clearing it also redraws the
    /// widgets' globe without it. Appearance and counting rules are settings, not
    /// data, and stay.
    func deleteEverything() throws {
        try store.deleteEverything()
        // Nothing is left to undo into, and the toast would offer to bring back one
        // record of a log the user has just chosen to erase.
        lastDeletion = nil
        home = nil
        reload()
    }
}
