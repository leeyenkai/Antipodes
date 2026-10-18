import AntipodesCore
import Foundation
import SwiftData

// CloudKit mirroring constrains every model in this file (AGENTS.md §4):
//
//   - every property is optional or has a default value
//   - no `@Attribute(.unique)` anywhere
//   - every relationship has an inverse and is optional or defaulted
//
// Enums and flexible dates are stored as their stable string codes rather than as Swift
// enums, so a future case cannot make an existing store unreadable. The mapping in
// `StoreMapping.swift` is the only place that interprets them.

@Model
public final class StoredTrip {
    public var identifier: UUID = UUID()
    public var name: String?
    public var notes: String?
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \StoredVisit.trip)
    public var visits: [StoredVisit]? = []

    @Relationship(deleteRule: .cascade, inverse: \StoredJourney.trip)
    public var journeys: [StoredJourney]? = []

    public init(identifier: UUID = UUID(), name: String? = nil, notes: String? = nil) {
        self.identifier = identifier
        self.name = name
        self.notes = notes
        createdAt = Date()
    }
}

@Model
public final class StoredVisit {
    public var identifier: UUID = UUID()

    // Place, flattened. Keeping these as columns rather than one encoded blob means a
    // future screen can filter by country without loading every visit.
    public var placeKindRaw: String = PlaceKind.custom.rawValue
    public var placeDatabaseID: Int?
    public var placeCustomID: UUID?
    public var placeName: String = ""
    public var latitude: Double?
    public var longitude: Double?
    public var countryCode: String?
    public var countryName: String?
    public var continentRaw: String?
    public var regionCode: String?
    public var regionName: String?
    public var cityID: Int?
    public var cityName: String?

    public var visitTypeRaw: String = VisitType.stayed.rawValue
    /// `FlexibleDate.exportString`: `2024-06-12`, `2024-06`, `2024`, a range, or empty.
    public var dateCode: String = ""
    public var rating: Int?
    public var notes: String?
    public var createdAt: Date = Date()

    public var trip: StoredTrip?

    public init() {}
}

@Model
public final class StoredJourney {
    public var identifier: UUID = UUID()
    public var title: String?
    public var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \StoredLeg.journey)
    public var legs: [StoredLeg]? = []

    public var trip: StoredTrip?

    public init(identifier: UUID = UUID(), title: String? = nil) {
        self.identifier = identifier
        self.title = title
        createdAt = Date()
    }
}

@Model
public final class StoredLeg {
    public var identifier: UUID = UUID()
    /// Position within its journey. A relationship array's order is not guaranteed
    /// under CloudKit, so leg order is stored explicitly.
    public var sequence: Int = 0

    public var modeRaw: String = TravelMode.flight.rawValue
    public var purposeRaw: String = TripPurpose.leisure.rawValue
    public var dateCode: String = ""

    public var originKindRaw: String = PlaceKind.airport.rawValue
    public var originDatabaseID: Int?
    public var originCustomID: UUID?
    public var originName: String = ""
    public var originLatitude: Double?
    public var originLongitude: Double?
    public var originCountryCode: String?
    public var originCountryName: String?
    public var originContinentRaw: String?
    public var originCityID: Int?
    public var originCityName: String?

    public var destinationKindRaw: String = PlaceKind.airport.rawValue
    public var destinationDatabaseID: Int?
    public var destinationCustomID: UUID?
    public var destinationName: String = ""
    public var destinationLatitude: Double?
    public var destinationLongitude: Double?
    public var destinationCountryCode: String?
    public var destinationCountryName: String?
    public var destinationContinentRaw: String?
    public var destinationCityID: Int?
    public var destinationCityName: String?

    public var storedPathLengthKm: Double?
    public var distanceKmOverride: Double?
    public var durationMinutesOverride: Int?

    public var operatorName: String?
    public var serviceNumber: String?
    public var vehicle: String?
    public var travelClass: String?
    public var seat: String?
    public var rating: Int?
    public var notes: String?

    public var journey: StoredJourney?

    public init() {}
}
