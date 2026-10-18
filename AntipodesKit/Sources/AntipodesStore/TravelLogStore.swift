import AntipodesCore
import Foundation
import SwiftData

/// The SwiftData container and the operations the UI performs on it.
///
/// Sync is CloudKit's private database, so the user's travel history never reaches a
/// server the developer controls (R-PRIV-2). There is no account step: if the user is
/// signed in to iCloud it syncs, and if not, the app works on-device exactly the same.
@MainActor
public final class TravelLogStore {
    public let container: ModelContainer

    public var context: ModelContext {
        container.mainContext
    }

    public static let schema = Schema([
        StoredTrip.self,
        StoredVisit.self,
        StoredJourney.self,
        StoredLeg.self,
    ])

    /// Opens the on-disk store, syncing through the user's private iCloud database.
    ///
    /// `cloudKitDatabase: .automatic` uses the entitlement's container when one is
    /// configured and falls back to local-only when it is not, so a development build
    /// without iCloud still runs.
    public init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(
            schema: Self.schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: inMemory ? .none : .automatic
        )
        container = try ModelContainer(for: Self.schema, configurations: configuration)
    }

    // MARK: - Reading

    /// Loads everything as plain values for the statistics engine.
    ///
    /// Reading the whole log is fine at M1 scale (thousands of records). When it stops
    /// being fine, the fix is incremental statistics, not leaking SwiftData into
    /// `AntipodesStats`.
    public func travelLog() throws -> TravelLog {
        let trips = try context.fetch(FetchDescriptor<StoredTrip>())
        let visits = try context.fetch(FetchDescriptor<StoredVisit>())
        let journeys = try context.fetch(FetchDescriptor<StoredJourney>())

        return TravelLog(
            trips: trips.map(\.asTrip),
            visits: visits.map(\.asVisit),
            journeys: journeys.map(\.asJourney)
        )
    }

    public func trip(id: UUID) throws -> StoredTrip? {
        try context.fetch(
            FetchDescriptor<StoredTrip>(predicate: #Predicate { $0.identifier == id })
        ).first
    }

    // MARK: - Writing

    @discardableResult
    public func createTrip(name: String?, notes: String? = nil) throws -> StoredTrip {
        let trip = StoredTrip(name: name, notes: notes)
        context.insert(trip)
        try context.save()
        return trip
    }

    /// Logs a visit. The place reference carries its own hierarchy, so a landmark
    /// brings its city, region and country with it (R-MODEL-6).
    @discardableResult
    public func logVisit(
        place: PlaceReference,
        visitType: VisitType,
        date: FlexibleDate,
        trip: StoredTrip? = nil,
        rating: Int? = nil,
        notes: String? = nil
    ) throws -> StoredVisit {
        let stored = StoredVisit()
        stored.apply(place: place)
        stored.visitTypeRaw = visitType.rawValue
        stored.dateCode = date.exportString
        stored.rating = rating
        stored.notes = notes
        stored.trip = trip
        context.insert(stored)
        try context.save()
        return stored
    }

    @discardableResult
    public func logJourney(
        legs: [JourneyLeg],
        trip: StoredTrip? = nil,
        title: String? = nil
    ) throws -> StoredJourney {
        let journey = StoredJourney(title: title)
        journey.trip = trip
        context.insert(journey)

        for (index, leg) in legs.enumerated() {
            let stored = StoredLeg()
            stored.apply(leg, sequence: index)
            stored.journey = journey
            context.insert(stored)
        }
        try context.save()
        return journey
    }

    public func delete(_ visit: StoredVisit) throws {
        context.delete(visit)
        try context.save()
    }

    public func delete(_ journey: StoredJourney) throws {
        context.delete(journey)
        try context.save()
    }

    /// Deletes a trip and everything in it. Visits and journeys cascade.
    public func delete(_ trip: StoredTrip) throws {
        context.delete(trip)
        try context.save()
    }

    // MARK: - Delete everything

    /// Erases every record, on this device and — through CloudKit — in the user's
    /// iCloud (R-PRIV-6).
    ///
    /// Removal propagates only while the device can reach iCloud. The UI must say so
    /// rather than implying the iCloud copy is already gone.
    public func deleteEverything() throws {
        try context.delete(model: StoredLeg.self)
        try context.delete(model: StoredJourney.self)
        try context.delete(model: StoredVisit.self)
        try context.delete(model: StoredTrip.self)
        try context.save()
    }
}
