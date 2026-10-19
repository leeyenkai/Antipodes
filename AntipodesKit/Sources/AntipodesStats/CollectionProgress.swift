import AntipodesCore
import Foundation

/// One member of a collection and whether it has been ticked off.
public struct CollectionMemberStatus: Hashable, Sendable, Identifiable {
    public var id: PlaceID {
        place.id
    }

    public let place: PlaceReference
    public let isVisited: Bool
    /// The earliest known day it was visited, where known.
    public let firstVisited: CalendarDate?
    /// Whether it is on the user's wishlist.
    public let isWishlisted: Bool
}

/// Progress through one curated collection (R-WISH-3): "US national parks: 12 visited".
public struct CollectionProgress: Hashable, Sendable, Identifiable {
    public var id: String {
        definition.id
    }

    public let definition: CollectionDefinition
    public let members: [CollectionMemberStatus]

    public var visitedCount: Int {
        members.count(where: \.isVisited)
    }

    public var total: Int {
        members.count
    }

    public var fraction: Double {
        total == 0 ? 0 : Double(visitedCount) / Double(total)
    }

    public var isComplete: Bool {
        total > 0 && visitedCount == total
    }

    /// The day the last member was ticked off, where every member's day is known.
    public var completedOn: CalendarDate? {
        guard isComplete else { return nil }
        let days = members.map(\.firstVisited)
        guard days.allSatisfy({ $0 != nil }) else { return nil }
        return days.compactMap(\.self).max()
    }

    /// Works out progress for every collection against the log.
    ///
    /// A member is ticked off by any visit that counts towards coverage and covers it —
    /// a landmark inside a member city ticks the city off (R-MODEL-6) — or, for a route,
    /// by a leg that rode it. Passing through Oslo on a train does not tick off Oslo,
    /// for the same reason it does not count towards coverage (R-CALC-1).
    public static func compute(
        collections: [CollectionDefinition],
        log: TravelLog,
        rules: CountingRules = .default
    ) -> [CollectionProgress] {
        let matcher = VisitMatcher(log: log, rules: rules)
        let wishlisted = Set(log.wishlist.compactMap { $0.place?.id })
        let wishlistedRoutes = Set(log.wishlist.compactMap(\.routeID))

        return collections.map { collection in
            CollectionProgress(
                definition: collection,
                members: collection.members.map { member in
                    let match = matcher.firstMatch(for: member)
                    let routeWished: Bool =
                        if case let .database(.route, row) = member.id {
                            wishlistedRoutes.contains(row)
                        } else {
                            false
                        }
                    return CollectionMemberStatus(
                        place: member,
                        isVisited: match.isVisited,
                        firstVisited: match.firstDay,
                        isWishlisted: wishlisted.contains(member.id) || routeWished
                    )
                }
            )
        }
    }
}

/// Whether a wishlist entry has been reached yet (R-WISH-4).
public struct WishlistStatus: Hashable, Sendable, Identifiable {
    public var id: UUID {
        item.id
    }

    public let item: WishlistItem
    public let isVisited: Bool
    public let firstVisited: CalendarDate?

    /// Ticks each wishlist entry off against the log, by the same rule collections use.
    /// Nothing is stored: delete the visit and the entry is open again.
    public static func compute(
        log: TravelLog,
        rules: CountingRules = .default
    ) -> [WishlistStatus] {
        let matcher = VisitMatcher(log: log, rules: rules)
        return log.wishlist.map { item in
            let match: VisitMatcher.Match =
                if let place = item.place {
                    matcher.firstMatch(for: place)
                } else if let route = item.routeID {
                    matcher.firstRide(of: route)
                } else {
                    VisitMatcher.Match(isVisited: false, firstDay: nil)
                }
            return WishlistStatus(
                item: item,
                isVisited: match.isVisited,
                firstVisited: match.firstDay
            )
        }
    }
}

/// The shared rule for "has the user been to this place yet".
struct VisitMatcher {
    struct Match {
        let isVisited: Bool
        let firstDay: CalendarDate?
    }

    let visits: [Visit]
    let legs: [JourneyLeg]

    init(log: TravelLog, rules: CountingRules) {
        visits = log.visits.filter { rules.countsTowardsCoverage($0.visitType) }
        legs = log.allLegs
    }

    func firstMatch(for target: PlaceReference) -> Match {
        if case let .database(.route, row) = target.id {
            return firstRide(of: row)
        }
        let matching = visits.filter { $0.place.covers(target) }
        return Match(
            isVisited: !matching.isEmpty,
            firstDay: matching.compactMap(\.date.sortDay).min()
        )
    }

    func firstRide(of routeID: Int64) -> Match {
        let matching = legs.filter { $0.routeID == routeID }
        return Match(
            isVisited: !matching.isEmpty,
            firstDay: matching.compactMap(\.date.sortDay).min()
        )
    }
}
