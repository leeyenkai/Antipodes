import Foundation

/// A trip: a container for the visits and journeys that belong together (R-MODEL-1).
public struct Trip: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    /// Trips may be unnamed; the UI falls back to dates and places.
    public var name: String?
    public var notes: String?
    /// When the trip was created in the app. Only used to order trips that have nothing
    /// dated in them yet; it is not when the trip happened.
    public var createdAt: Date?

    public init(
        id: UUID = UUID(),
        name: String? = nil,
        notes: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// One place, visited once (R-MODEL-2).
public struct Visit: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var place: PlaceReference
    public var visitType: VisitType
    public var date: FlexibleDate
    /// A visit can stand alone and be filed under a trip later (R-MODEL-3).
    public var tripID: UUID?
    public var rating: Int?
    public var notes: String?
    /// When it was logged, for ordering undated visits. Not when it happened.
    public var createdAt: Date?

    public init(
        id: UUID = UUID(),
        place: PlaceReference,
        visitType: VisitType = .stayed,
        date: FlexibleDate = .unknown,
        tripID: UUID? = nil,
        rating: Int? = nil,
        notes: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.place = place
        self.visitType = visitType
        self.date = date
        self.tripID = tripID
        self.rating = rating.map { min(5, max(1, $0)) }
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Decoded through the initialiser, so a backup's rating is kept within one to five
    /// stars like a typed one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            place: container.decode(PlaceReference.self, forKey: .place),
            visitType: container.decode(VisitType.self, forKey: .visitType),
            date: container.decode(FlexibleDate.self, forKey: .date),
            tripID: container.decodeIfPresent(UUID.self, forKey: .tripID),
            rating: container.decodeIfPresent(Int.self, forKey: .rating),
            notes: container.decodeIfPresent(String.self, forKey: .notes),
            createdAt: container.decodeIfPresent(Date.self, forKey: .createdAt)
        )
    }
}

/// Where a leg's distance came from, so a stat can say how solid its total is
/// (R-PATH-3, R-PATH-5).
public enum DistanceSource: String, Sendable, Codable, CaseIterable {
    /// The user typed the distance, which wins over everything.
    case userOverride
    /// Measured along real track, road or sea geometry, or a catalogue route's length.
    case storedPath
    /// Great-circle between the endpoints, and exact for a flight.
    case greatCircleExact
    /// Great-circle standing in for a surface path that has not been snapped yet.
    /// Stats must label these approximate.
    case greatCircleApproximate
    /// No distance could be worked out at all.
    case unavailable

    public var isApproximate: Bool {
        self == .greatCircleApproximate
    }
}

/// The time between one leg arriving and the next departing (R-JLOG-4).
public struct Connection: Hashable, Sendable {
    public let arrivingLegID: UUID
    public let departingLegID: UUID
    /// `nil` when either time is missing, or the zones needed to compare them are.
    public let minutes: Int?
    /// The user marked the connection as missed.
    public let isMissed: Bool
    /// The next leg does not start where the last one ended — a gap the user filled
    /// some other way, such as a taxi across town.
    public let changesPlace: Bool
}

/// A journey: one or more legs travelled as a single movement (R-MODEL-4).
public struct Journey: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var legs: [JourneyLeg]
    public var tripID: UUID?
    public var title: String?

    public init(
        id: UUID = UUID(),
        legs: [JourneyLeg] = [],
        tripID: UUID? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.legs = legs
        self.tripID = tripID
        self.title = title
    }

    public var totalDistanceKm: Double {
        legs.reduce(0) { $0 + $1.distanceKm }
    }

    public var modes: Set<TravelMode> {
        Set(legs.map(\.mode))
    }

    /// The journey's date, taken from its earliest dated leg.
    public var date: FlexibleDate {
        legs.map(\.date).filter(\.isKnown).min() ?? .unknown
    }

    public var origin: PlaceReference? {
        legs.first?.origin
    }

    public var destination: PlaceReference? {
        legs.last?.destination
    }

    /// Every change between consecutive legs, in order.
    public var connections: [Connection] {
        zip(legs, legs.dropFirst()).map { arriving, departing in
            var minutes: Int?
            if let arrival = arriving.times.bestArrival,
               let departure = departing.times.bestDeparture {
                minutes = JourneyLeg.minutes(
                    from: arrival, in: arriving.destination,
                    to: departure, in: departing.origin
                )
            }
            return Connection(
                arrivingLegID: arriving.id,
                departingLegID: departing.id,
                minutes: minutes,
                isMissed: departing.missedConnection,
                changesPlace: arriving.destination.id != departing.origin.id
            )
        }
    }

    /// Total minutes from first departure to last arrival, where every leg's duration
    /// and every connection are known.
    public var elapsedMinutes: Int? {
        var total = 0
        for leg in legs {
            guard let minutes = leg.durationMinutes else { return nil }
            total += minutes
        }
        for connection in connections {
            guard let minutes = connection.minutes, minutes >= 0 else { return nil }
            total += minutes
        }
        return legs.isEmpty ? nil : total
    }
}

/// Somewhere the user wants to go (R-WISH-1).
///
/// A wishlist entry is never ticked off by hand: whether it has been visited is worked
/// out from the log every time, so logging a visit ticks it off automatically and
/// deleting that visit puts it back (R-WISH-4).
public struct WishlistItem: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    /// The place, or `nil` for a catalogue route.
    public var place: PlaceReference?
    public var routeID: Int64?
    public var routeName: String?
    public var notes: String?
    public var createdAt: Date?

    public init(
        id: UUID = UUID(),
        place: PlaceReference? = nil,
        routeID: Int64? = nil,
        routeName: String? = nil,
        notes: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.place = place
        self.routeID = routeID
        self.routeName = routeName
        self.notes = notes
        self.createdAt = createdAt
    }

    public var title: String {
        place?.name ?? routeName ?? "Route"
    }
}

/// Everything the user has logged, as plain values.
///
/// This is what the statistics engine reads. It is deliberately free of SwiftData so
/// the whole engine can be tested without a model container (decision D-2).
public struct TravelLog: Hashable, Sendable {
    public var trips: [Trip]
    public var visits: [Visit]
    public var journeys: [Journey]
    public var wishlist: [WishlistItem]

    public static let empty = TravelLog()

    public init(
        trips: [Trip] = [],
        visits: [Visit] = [],
        journeys: [Journey] = [],
        wishlist: [WishlistItem] = []
    ) {
        self.trips = trips
        self.visits = visits
        self.journeys = journeys
        self.wishlist = wishlist
    }

    public var allLegs: [JourneyLeg] {
        journeys.flatMap(\.legs)
    }

    /// One record per identity, keeping the first of each, and one leg per identity
    /// within each journey.
    ///
    /// Synced storage cannot promise that an identity is held once, and a record held
    /// twice must not count twice in any statistic (R-CALC-5).
    public func deduplicated() -> TravelLog {
        func firstOfEach<Item: Identifiable>(_ items: [Item]) -> [Item] {
            var seen = Set<Item.ID>()
            return items.filter { seen.insert($0.id).inserted }
        }
        return TravelLog(
            trips: firstOfEach(trips),
            visits: firstOfEach(visits),
            journeys: firstOfEach(journeys).map { journey in
                var copy = journey
                copy.legs = firstOfEach(journey.legs)
                return copy
            },
            wishlist: firstOfEach(wishlist)
        )
    }

    /// Whether anything has been *logged*. A wishlist on its own is somewhere the user
    /// has not been yet, so it does not make the log non-empty.
    public var isEmpty: Bool {
        trips.isEmpty && visits.isEmpty && journeys.isEmpty
    }

    /// Every bundled place the log refers to — visited, at either end of a leg, or
    /// implied as a landmark's city (R-MODEL-6) — which is what the attribute and
    /// capital statistics need facts for. Logging only the Eiffel Tower still makes
    /// Paris a capital visited.
    public var referencedDatabasePlaceIDs: Set<PlaceID> {
        var ids: Set<PlaceID> = []
        func add(_ place: PlaceReference) {
            if case .database = place.id {
                ids.insert(place.id)
            }
            if let city = place.impliedCityID {
                ids.insert(.database(.city, city))
            }
        }
        for visit in visits {
            add(visit.place)
        }
        for leg in allLegs {
            add(leg.origin)
            add(leg.destination)
        }
        return ids
    }

    public func visits(inTrip tripID: UUID) -> [Visit] {
        visits.filter { $0.tripID == tripID }
    }

    public func journeys(inTrip tripID: UUID) -> [Journey] {
        journeys.filter { $0.tripID == tripID }
    }

    public func trip(id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    /// The part of the log that belongs to one trip, with the trip itself.
    public func restricted(toTrip tripID: UUID) -> TravelLog {
        TravelLog(
            trips: trips.filter { $0.id == tripID },
            visits: visits(inTrip: tripID),
            journeys: journeys(inTrip: tripID)
        )
    }

    /// The part of the log filed under one calendar year (D-23): a range belongs to the
    /// year it began. Undated records belong to no year.
    public func restricted(toYear year: Int) -> TravelLog {
        TravelLog(
            trips: trips,
            visits: visits.filter { $0.date.year == year },
            journeys: journeys.compactMap { journey in
                let legs = journey.legs.filter { $0.date.year == year }
                guard !legs.isEmpty else { return nil }
                var copy = journey
                copy.legs = legs
                return copy
            }
        )
    }
}

extension TravelLog: Codable {
    private enum CodingKeys: String, CodingKey {
        case trips, visits, journeys, wishlist
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            trips: container.decodeIfPresent([Trip].self, forKey: .trips) ?? [],
            visits: container.decodeIfPresent([Visit].self, forKey: .visits) ?? [],
            journeys: container.decodeIfPresent([Journey].self, forKey: .journeys) ?? [],
            wishlist: container.decodeIfPresent([WishlistItem].self, forKey: .wishlist) ?? []
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(trips, forKey: .trips)
        try container.encode(visits, forKey: .visits)
        try container.encode(journeys, forKey: .journeys)
        try container.encode(wishlist, forKey: .wishlist)
    }
}
