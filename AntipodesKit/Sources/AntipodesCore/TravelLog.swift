import Foundation

/// A trip: a container for the visits and journeys that belong together (R-MODEL-1).
public struct Trip: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    /// Trips may be unnamed; the UI falls back to dates and places.
    public var name: String?
    public var notes: String?

    public init(id: UUID = UUID(), name: String? = nil, notes: String? = nil) {
        self.id = id
        self.name = name
        self.notes = notes
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

    public init(
        id: UUID = UUID(),
        place: PlaceReference,
        visitType: VisitType = .stayed,
        date: FlexibleDate = .unknown,
        tripID: UUID? = nil,
        rating: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.place = place
        self.visitType = visitType
        self.date = date
        self.tripID = tripID
        self.rating = rating.map { min(5, max(1, $0)) }
        self.notes = notes
    }
}

/// Where a leg's distance came from, so a stat can say how solid its total is
/// (R-PATH-3, R-PATH-5).
public enum DistanceSource: String, Sendable, Codable, CaseIterable {
    /// The user typed the distance, which wins over everything.
    case userOverride
    /// Measured along real track, road or sea geometry.
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

/// One stage of a journey: a single vehicle from one place to another (§5.2).
///
/// Only `mode`, `origin` and `destination` are required (R-LEG-1).
public struct JourneyLeg: Identifiable, Hashable, Sendable, Codable {
    public var id: UUID
    public var mode: TravelMode
    public var origin: PlaceReference
    public var destination: PlaceReference
    public var date: FlexibleDate
    public var purpose: TripPurpose

    /// Length of the real path, where the pipeline or on-device snapping produced one.
    public var storedPathLengthKm: Double?
    /// The user's own figure, which beats any computed one.
    public var distanceKmOverride: Double?
    public var durationMinutesOverride: Int?

    public var operatorName: String?
    public var serviceNumber: String?
    public var vehicle: String?
    public var travelClass: String?
    public var seat: String?
    public var rating: Int?
    public var notes: String?

    public init(
        id: UUID = UUID(),
        mode: TravelMode,
        origin: PlaceReference,
        destination: PlaceReference,
        date: FlexibleDate = .unknown,
        purpose: TripPurpose = .leisure,
        storedPathLengthKm: Double? = nil,
        distanceKmOverride: Double? = nil,
        durationMinutesOverride: Int? = nil,
        operatorName: String? = nil,
        serviceNumber: String? = nil,
        vehicle: String? = nil,
        travelClass: String? = nil,
        seat: String? = nil,
        rating: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.origin = origin
        self.destination = destination
        self.date = date
        self.purpose = purpose
        self.storedPathLengthKm = storedPathLengthKm
        self.distanceKmOverride = distanceKmOverride
        self.durationMinutesOverride = durationMinutesOverride
        self.operatorName = operatorName
        self.serviceNumber = serviceNumber
        self.vehicle = vehicle
        self.travelClass = travelClass
        self.seat = seat
        self.rating = rating.map { min(5, max(1, $0)) }
        self.notes = notes
    }

    /// Distance and where it came from, resolved in one place so every caller agrees.
    ///
    /// Order: the user's override, then a real stored path, then the great circle —
    /// exact for a flight, flagged approximate for anything that should have followed
    /// the ground (R-PATH-5).
    public var distance: (kilometres: Double, source: DistanceSource) {
        if let override = distanceKmOverride, override >= 0 {
            return (override, .userOverride)
        }
        if let stored = storedPathLengthKm, stored >= 0 {
            return (stored, .storedPath)
        }
        guard let from = origin.coordinate, let to = destination.coordinate else {
            return (0, .unavailable)
        }
        let kilometres = GreatCircle.distanceKm(from: from, to: to)
        return (kilometres, mode.greatCircleIsExact ? .greatCircleExact : .greatCircleApproximate)
    }

    public var distanceKm: Double {
        distance.kilometres
    }

    public var distanceSource: DistanceSource {
        distance.source
    }

    /// The arc to draw on the globe. A flight curves; anything else is a straight
    /// stand-in until a real path exists.
    public func pathForDisplay(segments: Int = 64) -> [Coordinate] {
        guard let from = origin.coordinate, let to = destination.coordinate else { return [] }
        return GreatCircle.arc(from: from, to: to, segments: segments)
    }
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
}

/// Everything the user has logged, as plain values.
///
/// This is what the statistics engine reads. It is deliberately free of SwiftData so
/// the whole engine can be tested without a model container (decision D-2).
public struct TravelLog: Hashable, Sendable, Codable {
    public var trips: [Trip]
    public var visits: [Visit]
    public var journeys: [Journey]

    public static let empty = TravelLog()

    public init(trips: [Trip] = [], visits: [Visit] = [], journeys: [Journey] = []) {
        self.trips = trips
        self.visits = visits
        self.journeys = journeys
    }

    public var allLegs: [JourneyLeg] {
        journeys.flatMap(\.legs)
    }

    public var isEmpty: Bool {
        trips.isEmpty && visits.isEmpty && journeys.isEmpty
    }

    public func visits(inTrip tripID: UUID) -> [Visit] {
        visits.filter { $0.tripID == tripID }
    }

    public func journeys(inTrip tripID: UUID) -> [Journey] {
        journeys.filter { $0.tripID == tripID }
    }
}
