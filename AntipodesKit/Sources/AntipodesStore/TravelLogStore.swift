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

    public static let schema = Schema(versionedSchema: AntipodesSchemaV1.self)

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
        container = try ModelContainer(
            for: Self.schema,
            migrationPlan: AntipodesMigrationPlan.self,
            configurations: configuration
        )
    }

    // MARK: - Reading

    /// Loads everything as plain values for the statistics engine.
    ///
    /// Reading the whole log is fine at v1 scale (thousands of records). When it stops
    /// being fine, the fix is incremental statistics, not leaking SwiftData into
    /// `AntipodesStats`.
    ///
    /// CloudKit cannot enforce a unique identity, so the same record can exist as more
    /// than one row — a backup restored on two devices before they synced, say. Rows
    /// are read oldest first and folded into one record per identity, so a copy never
    /// counts twice in a statistic. The extra rows are left in place rather than
    /// deleted: two devices choosing different rows to keep would delete both through
    /// sync. Every write below goes to all of a record's rows instead, so the copies
    /// stay identical.
    public func travelLog() throws -> TravelLog {
        let trips = try context.fetch(FetchDescriptor<StoredTrip>(sortBy: [.init(\.createdAt)]))
        let visits = try context.fetch(FetchDescriptor<StoredVisit>(sortBy: [.init(\.createdAt)]))
        let journeys = try context
            .fetch(FetchDescriptor<StoredJourney>(sortBy: [.init(\.createdAt)]))
        let wishlist = try context
            .fetch(FetchDescriptor<StoredWishlistItem>(sortBy: [.init(\.createdAt)]))

        return TravelLog(
            trips: trips.map(\.asTrip),
            visits: visits.map(\.asVisit),
            journeys: journeys.map(\.asJourney),
            wishlist: wishlist.map(\.asWishlistItem)
        ).deduplicated()
    }

    /// The oldest row holding a trip — the one new links point at.
    public func trip(id: UUID) throws -> StoredTrip? {
        try trips(id: id).first
    }

    /// Every row holding a trip, oldest first. Normally one.
    func trips(id: UUID) throws -> [StoredTrip] {
        try context.fetch(FetchDescriptor<StoredTrip>(
            predicate: #Predicate { $0.identifier == id },
            sortBy: [SortDescriptor(\.createdAt)]
        ))
    }

    func visits(id: UUID) throws -> [StoredVisit] {
        try context
            .fetch(FetchDescriptor<StoredVisit>(predicate: #Predicate { $0.identifier == id }))
    }

    func journeys(id: UUID) throws -> [StoredJourney] {
        try context
            .fetch(FetchDescriptor<StoredJourney>(predicate: #Predicate { $0.identifier == id }))
    }

    func wishlistItems(id: UUID) throws -> [StoredWishlistItem] {
        try context
            .fetch(FetchDescriptor<StoredWishlistItem>(predicate: #Predicate { $0.identifier == id
            }))
    }

    /// Saves, or puts the context back as it was if the save fails, so a failed write
    /// never leaves half a change sitting in memory to be saved by the next one.
    func saveOrRollBack() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Trips

    @discardableResult
    public func createTrip(name: String?, notes: String? = nil) throws -> StoredTrip {
        let trip = StoredTrip(name: name, notes: notes)
        context.insert(trip)
        try saveOrRollBack()
        return trip
    }

    public func updateTrip(_ trip: Trip) throws {
        for stored in try trips(id: trip.id) {
            stored.name = trip.name?.trimmedOrNil
            stored.notes = trip.notes?.trimmedOrNil
        }
        try saveOrRollBack()
    }

    /// Deletes a trip. By default its visits and journeys stay in the log, unfiled —
    /// the travel happened whether or not the trip that grouped it still exists
    /// (R-MODEL-3). Pass `deletingContents` to remove them too.
    public func deleteTrip(id: UUID, deletingContents: Bool) throws {
        for stored in try trips(id: id) {
            if !deletingContents {
                for visit in stored.visits ?? [] {
                    visit.trip = nil
                }
                for journey in stored.journeys ?? [] {
                    journey.trip = nil
                }
            }
            context.delete(stored)
        }
        try saveOrRollBack()
    }

    // MARK: - Visits

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
        try saveOrRollBack()
        return stored
    }

    /// Logs many visits in one save, so an import lands whole or not at all.
    public func logVisits(
        _ visits: [(place: PlaceReference, visitType: VisitType, date: FlexibleDate)],
        trip: StoredTrip? = nil
    ) throws {
        for visit in visits {
            let stored = StoredVisit()
            stored.apply(place: visit.place)
            stored.visitTypeRaw = visit.visitType.rawValue
            stored.dateCode = visit.date.exportString
            stored.trip = trip
            context.insert(stored)
        }
        try saveOrRollBack()
    }

    /// Writes every field of an edited visit back, including which trip it is in.
    public func updateVisit(_ visit: Visit) throws {
        let destination = try visit.tripID.flatMap { try trip(id: $0) }
        for stored in try visits(id: visit.id) {
            stored.apply(visit)
            stored.trip = destination
        }
        try saveOrRollBack()
    }

    /// Writes many edited visits back in one save.
    public func updateVisits(_ edited: [Visit]) throws {
        for visit in edited {
            let destination = try visit.tripID.flatMap { try trip(id: $0) }
            for stored in try visits(id: visit.id) {
                stored.apply(visit)
                stored.trip = destination
            }
        }
        try saveOrRollBack()
    }

    /// Files many visits under one trip at once, or takes them out of any trip.
    public func moveVisits(_ ids: [UUID], toTrip tripID: UUID?) throws {
        let destination = try tripID.flatMap { try trip(id: $0) }
        for id in ids {
            for stored in try visits(id: id) {
                stored.trip = destination
            }
        }
        try saveOrRollBack()
    }

    public func deleteVisits(_ ids: [UUID]) throws {
        for id in ids {
            for stored in try visits(id: id) {
                context.delete(stored)
            }
        }
        try saveOrRollBack()
    }

    // MARK: - Journeys

    @discardableResult
    public func logJourney(
        legs: [JourneyLeg],
        trip: StoredTrip? = nil,
        title: String? = nil
    ) throws -> StoredJourney {
        let journey = insertJourney(legs: legs, trip: trip, title: title)
        try saveOrRollBack()
        return journey
    }

    /// Logs many journeys in one save, so an import lands whole or not at all.
    public func logJourneys(_ journeys: [[JourneyLeg]], trip: StoredTrip? = nil) throws {
        for legs in journeys {
            insertJourney(legs: legs, trip: trip, title: nil)
        }
        try saveOrRollBack()
    }

    @discardableResult
    private func insertJourney(
        legs: [JourneyLeg],
        trip: StoredTrip?,
        title: String?
    ) -> StoredJourney {
        let journey = StoredJourney(title: title)
        journey.trip = trip
        context.insert(journey)

        for (index, leg) in legs.enumerated() {
            let stored = StoredLeg()
            stored.apply(leg, sequence: index)
            stored.journey = journey
            context.insert(stored)
        }
        return journey
    }

    /// Replaces a journey's legs, title and trip with an edited copy.
    ///
    /// Legs are matched by identity: an edited leg is updated in place, a new one is
    /// inserted, and one the user removed is deleted — so a sync conflict touches only
    /// what actually changed.
    public func updateJourney(_ journey: Journey) throws {
        let destination = try journey.tripID.flatMap { try trip(id: $0) }
        for stored in try journeys(id: journey.id) {
            stored.title = journey.title?.trimmedOrNil
            stored.trip = destination

            var existing = Dictionary(
                (stored.legs ?? []).map { ($0.identifier, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for (index, leg) in journey.legs.enumerated() {
                let row: StoredLeg
                if let found = existing.removeValue(forKey: leg.id) {
                    row = found
                } else {
                    row = StoredLeg()
                    row.journey = stored
                    context.insert(row)
                }
                row.apply(leg, sequence: index)
            }
            for removed in existing.values {
                context.delete(removed)
            }
        }
        try saveOrRollBack()
    }

    public func moveJourneys(_ ids: [UUID], toTrip tripID: UUID?) throws {
        let destination = try tripID.flatMap { try trip(id: $0) }
        for id in ids {
            for stored in try journeys(id: id) {
                stored.trip = destination
            }
        }
        try saveOrRollBack()
    }

    public func deleteJourneys(_ ids: [UUID]) throws {
        for id in ids {
            for stored in try journeys(id: id) {
                context.delete(stored)
            }
        }
        try saveOrRollBack()
    }

    // MARK: - Wishlist

    @discardableResult
    public func addToWishlist(_ item: WishlistItem) throws -> StoredWishlistItem {
        let stored = StoredWishlistItem()
        stored.apply(item)
        context.insert(stored)
        try saveOrRollBack()
        return stored
    }

    public func updateWishlistItem(_ item: WishlistItem) throws {
        for stored in try wishlistItems(id: item.id) {
            stored.apply(item)
        }
        try saveOrRollBack()
    }

    public func removeFromWishlist(_ ids: [UUID]) throws {
        for id in ids {
            for stored in try wishlistItems(id: id) {
                context.delete(stored)
            }
        }
        try saveOrRollBack()
    }

    // MARK: - Delete everything

    /// Erases every record, on this device and — through CloudKit — in the user's
    /// iCloud (R-PRIV-6).
    ///
    /// Each object is deleted individually rather than with a batch delete. A batch
    /// delete goes straight to the store without the change tracking CloudKit mirroring
    /// exports from, so on some systems the iCloud copy would survive it — exactly the
    /// failure a "delete everything" button must not have.
    ///
    /// Removal propagates only while the device can reach iCloud. The UI must say so
    /// rather than implying the iCloud copy is already gone.
    public func deleteEverything() throws {
        for leg in try context.fetch(FetchDescriptor<StoredLeg>()) {
            context.delete(leg)
        }
        for journey in try context.fetch(FetchDescriptor<StoredJourney>()) {
            context.delete(journey)
        }
        for visit in try context.fetch(FetchDescriptor<StoredVisit>()) {
            context.delete(visit)
        }
        for trip in try context.fetch(FetchDescriptor<StoredTrip>()) {
            context.delete(trip)
        }
        for item in try context.fetch(FetchDescriptor<StoredWishlistItem>()) {
            context.delete(item)
        }
        try saveOrRollBack()
    }
}

extension String {
    /// `nil` for an empty or whitespace-only string, the trimmed string otherwise.
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
