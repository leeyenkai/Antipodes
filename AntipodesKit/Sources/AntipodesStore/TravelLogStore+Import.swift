import AntipodesCore
import Foundation
import SwiftData

/// Restoring a backup: adding what a file holds that the store does not, by identity.
public extension TravelLogStore {
    /// Adds every record in `log` that the store does not already hold, matched by
    /// identity, and reports how many of each it added.
    ///
    /// Importing the same export twice adds nothing the second time, which is what
    /// makes an export a safe backup to restore from (R-LOG-8, R-LOG-9).
    @discardableResult
    func merge(_ log: TravelLog) throws -> ImportCounts {
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
            if visit.tripID != nil, stored.trip == nil {
                counts.unfiled += 1
            }
            context.insert(stored)
            counts.visits += 1
        }
        for journey in log.journeys where !existing.journeys.contains(journey.id) {
            let stored = StoredJourney(identifier: journey.id, title: journey.title)
            stored.trip = journey.tripID.flatMap { tripsByID[$0] }
            if journey.tripID != nil, stored.trip == nil {
                counts.unfiled += 1
            }
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
        try saveOrRollBack()
        return counts
    }

    /// What `merge(_:)` would add, by the same identity rule, without adding anything —
    /// so the user can see what a file holds and say yes first (R-NAV-2).
    func mergePreview(_ log: TravelLog) throws -> ImportCounts {
        let existing = try existingIdentifiers()
        var counts = ImportCounts()
        counts.trips = log.trips.count { !existing.trips.contains($0.id) }
        counts.visits = log.visits.count { !existing.visits.contains($0.id) }
        let journeys = log.journeys.filter { !existing.journeys.contains($0.id) }
        counts.journeys = journeys.count
        counts.legs = journeys.reduce(0) { $0 + $1.legs.count }
        counts.wishlist = log.wishlist.count { !existing.wishlist.contains($0.id) }
        let knownTrips = existing.trips.union(log.trips.map(\.id))
        let newVisits = log.visits.filter { !existing.visits.contains($0.id) }
        counts.unfiled = newVisits.count { $0.tripID.map { !knownTrips.contains($0) } ?? false }
            + journeys.count { $0.tripID.map { !knownTrips.contains($0) } ?? false }
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
}

/// What an import added, for the confirmation the user sees.
public struct ImportCounts: Hashable, Sendable {
    public var trips = 0
    public var visits = 0
    public var journeys = 0
    public var legs = 0
    public var wishlist = 0
    /// Visits and journeys whose trip is neither in the file nor in the log, which
    /// arrive unfiled rather than not at all.
    public var unfiled = 0

    public init() {}

    public var total: Int {
        trips + visits + journeys + wishlist
    }
}
