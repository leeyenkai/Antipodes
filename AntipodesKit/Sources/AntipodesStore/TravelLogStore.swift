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
        StoredWishlistItem.self,
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
    /// Reading the whole log is fine at v1 scale (thousands of records). When it stops
    /// being fine, the fix is incremental statistics, not leaking SwiftData into
    /// `AntipodesStats`.
    public func travelLog() throws -> TravelLog {
        let trips = try context.fetch(FetchDescriptor<StoredTrip>())
        let visits = try context.fetch(FetchDescriptor<StoredVisit>())
        let journeys = try context.fetch(FetchDescriptor<StoredJourney>())
        let wishlist = try context.fetch(FetchDescriptor<StoredWishlistItem>())

        return TravelLog(
            trips: trips.map(\.asTrip),
            visits: visits.map(\.asVisit),
            journeys: journeys.map(\.asJourney),
            wishlist: wishlist.map(\.asWishlistItem)
        )
    }

    public func trip(id: UUID) throws -> StoredTrip? {
        try context.fetch(
            FetchDescriptor<StoredTrip>(predicate: #Predicate { $0.identifier == id })
        ).first
    }

    public func visit(id: UUID) throws -> StoredVisit? {
        try context.fetch(
            FetchDescriptor<StoredVisit>(predicate: #Predicate { $0.identifier == id })
        ).first
    }

    public func journey(id: UUID) throws -> StoredJourney? {
        try context.fetch(
            FetchDescriptor<StoredJourney>(predicate: #Predicate { $0.identifier == id })
        ).first
    }

    public func wishlistItem(id: UUID) throws -> StoredWishlistItem? {
        try context.fetch(
            FetchDescriptor<StoredWishlistItem>(predicate: #Predicate { $0.identifier == id })
        ).first
    }

    // MARK: - Trips

    @discardableResult
    public func createTrip(name: String?, notes: String? = nil) throws -> StoredTrip {
        let trip = StoredTrip(name: name, notes: notes)
        context.insert(trip)
        try context.save()
        return trip
    }

    public func updateTrip(_ trip: Trip) throws {
        guard let stored = try self.trip(id: trip.id) else { return }
        stored.name = trip.name?.trimmedOrNil
        stored.notes = trip.notes?.trimmedOrNil
        try context.save()
    }

    /// Deletes a trip. By default its visits and journeys stay in the log, unfiled —
    /// the travel happened whether or not the trip that grouped it still exists
    /// (R-MODEL-3). Pass `deletingContents` to remove them too.
    public func deleteTrip(id: UUID, deletingContents: Bool) throws {
        guard let stored = try trip(id: id) else { return }
        if !deletingContents {
            for visit in stored.visits ?? [] {
                visit.trip = nil
            }
            for journey in stored.journeys ?? [] {
                journey.trip = nil
            }
        }
        context.delete(stored)
        try context.save()
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
        try context.save()
        return stored
    }

    /// Writes every field of an edited visit back, including which trip it is in.
    public func updateVisit(_ visit: Visit) throws {
        guard let stored = try self.visit(id: visit.id) else { return }
        stored.apply(visit)
        stored.trip = try visit.tripID.flatMap { try trip(id: $0) }
        try context.save()
    }

    /// Files many visits under one trip at once, or takes them out of any trip.
    public func moveVisits(_ ids: [UUID], toTrip tripID: UUID?) throws {
        let destination = try tripID.flatMap { try trip(id: $0) }
        for id in ids {
            try visit(id: id)?.trip = destination
        }
        try context.save()
    }

    public func deleteVisits(_ ids: [UUID]) throws {
        for id in ids {
            if let stored = try visit(id: id) {
                context.delete(stored)
            }
        }
        try context.save()
    }

    // MARK: - Journeys

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

    /// Replaces a journey's legs, title and trip with an edited copy.
    ///
    /// Legs are matched by identity: an edited leg is updated in place, a new one is
    /// inserted, and one the user removed is deleted — so a sync conflict touches only
    /// what actually changed.
    public func updateJourney(_ journey: Journey) throws {
        guard let stored = try self.journey(id: journey.id) else { return }
        stored.title = journey.title?.trimmedOrNil
        stored.trip = try journey.tripID.flatMap { try trip(id: $0) }

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
        try context.save()
    }

    public func moveJourneys(_ ids: [UUID], toTrip tripID: UUID?) throws {
        let destination = try tripID.flatMap { try trip(id: $0) }
        for id in ids {
            try journey(id: id)?.trip = destination
        }
        try context.save()
    }

    public func deleteJourneys(_ ids: [UUID]) throws {
        for id in ids {
            if let stored = try journey(id: id) {
                context.delete(stored)
            }
        }
        try context.save()
    }

    // MARK: - Wishlist

    @discardableResult
    public func addToWishlist(_ item: WishlistItem) throws -> StoredWishlistItem {
        let stored = StoredWishlistItem()
        stored.apply(item)
        context.insert(stored)
        try context.save()
        return stored
    }

    public func updateWishlistItem(_ item: WishlistItem) throws {
        guard let stored = try wishlistItem(id: item.id) else { return }
        stored.apply(item)
        try context.save()
    }

    public func removeFromWishlist(_ ids: [UUID]) throws {
        for id in ids {
            if let stored = try wishlistItem(id: id) {
                context.delete(stored)
            }
        }
        try context.save()
    }

    // MARK: - Import

    /// Adds every record in `log` that the store does not already hold, matched by
    /// identity, and reports how many of each it added.
    ///
    /// Importing the same export twice adds nothing the second time, which is what
    /// makes an export a safe backup to restore from (R-LOG-8, R-LOG-9).
    @discardableResult
    public func merge(_ log: TravelLog) throws -> ImportCounts {
        var counts = ImportCounts()
        let existing = try existingIdentifiers()

        var tripsByID: [UUID: StoredTrip] = [:]
        for trip in try context.fetch(FetchDescriptor<StoredTrip>()) {
            tripsByID[trip.identifier] = trip
        }
        for trip in log.trips where !existing.trips.contains(trip.id) {
            let stored = StoredTrip(identifier: trip.id, name: trip.name, notes: trip.notes)
            if let created = trip.createdAt {
                stored.createdAt = created
            }
            context.insert(stored)
            tripsByID[trip.id] = stored
            counts.trips += 1
        }
        for visit in log.visits where !existing.visits.contains(visit.id) {
            let stored = StoredVisit()
            stored.apply(visit)
            if let created = visit.createdAt {
                stored.createdAt = created
            }
            stored.trip = visit.tripID.flatMap { tripsByID[$0] }
            context.insert(stored)
            counts.visits += 1
        }
        for journey in log.journeys where !existing.journeys.contains(journey.id) {
            let stored = StoredJourney(identifier: journey.id, title: journey.title)
            stored.trip = journey.tripID.flatMap { tripsByID[$0] }
            context.insert(stored)
            for (index, leg) in journey.legs.enumerated() {
                let row = StoredLeg()
                row.apply(leg, sequence: index)
                row.journey = stored
                context.insert(row)
            }
            counts.journeys += 1
            counts.legs += journey.legs.count
        }
        for item in log.wishlist where !existing.wishlist.contains(item.id) {
            let stored = StoredWishlistItem()
            stored.apply(item)
            context.insert(stored)
            counts.wishlist += 1
        }
        try context.save()
        return counts
    }

    /// What `merge(_:)` would add, by the same identity rule, without adding anything —
    /// so the user can see what a file holds and say yes first (R-NAV-2).
    public func mergePreview(_ log: TravelLog) throws -> ImportCounts {
        let existing = try existingIdentifiers()
        var counts = ImportCounts()
        counts.trips = log.trips.count { !existing.trips.contains($0.id) }
        counts.visits = log.visits.count { !existing.visits.contains($0.id) }
        let journeys = log.journeys.filter { !existing.journeys.contains($0.id) }
        counts.journeys = journeys.count
        counts.legs = journeys.reduce(0) { $0 + $1.legs.count }
        counts.wishlist = log.wishlist.count { !existing.wishlist.contains($0.id) }
        return counts
    }

    /// The identity of every record already stored, which is what `merge(_:)` matches on.
    private struct ExistingIdentifiers {
        let trips: Set<UUID>
        let visits: Set<UUID>
        let journeys: Set<UUID>
        let wishlist: Set<UUID>
    }

    private func existingIdentifiers() throws -> ExistingIdentifiers {
        try ExistingIdentifiers(
            trips: Set(context.fetch(FetchDescriptor<StoredTrip>()).map(\.identifier)),
            visits: Set(context.fetch(FetchDescriptor<StoredVisit>()).map(\.identifier)),
            journeys: Set(context.fetch(FetchDescriptor<StoredJourney>()).map(\.identifier)),
            wishlist: Set(context.fetch(FetchDescriptor<StoredWishlistItem>()).map(\.identifier))
        )
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
        try context.save()
    }
}

/// What an import added, for the confirmation the user sees.
public struct ImportCounts: Hashable, Sendable {
    public var trips = 0
    public var visits = 0
    public var journeys = 0
    public var legs = 0
    public var wishlist = 0

    public init() {}

    public var total: Int {
        trips + visits + journeys + wishlist
    }
}

extension String {
    /// `nil` for an empty or whitespace-only string, the trimmed string otherwise.
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
