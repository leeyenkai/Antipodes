import AntipodesCore
import Foundation

// Translation between the stored models and the value types the rest of the app uses.
//
// This is the only file that knows both worlds. Keeping it in one place is what lets
// the statistics engine stay free of SwiftData (decision D-2).

extension PlaceKind {
    static func decoded(_ raw: String) -> PlaceKind {
        PlaceKind(rawValue: raw) ?? .custom
    }
}

/// The flattened columns of one place, as every stored model that holds a place keeps
/// them. One shape, so the visit, both ends of a leg and a wishlist entry encode a place
/// identically.
struct PlaceColumns {
    var kindRaw: String
    var databaseID: Int?
    var customID: UUID?
    var name: String
    var latitude: Double?
    var longitude: Double?
    var countryCode: String?
    var countryName: String?
    var continentRaw: String?
    var regionCode: String?
    var regionName: String?
    var cityID: Int?
    var cityName: String?
    var timeZoneIdentifier: String?
    var code: String?

    init(
        kindRaw: String,
        databaseID: Int?,
        customID: UUID?,
        name: String,
        latitude: Double?,
        longitude: Double?,
        countryCode: String?,
        countryName: String?,
        continentRaw: String?,
        regionCode: String?,
        regionName: String?,
        cityID: Int?,
        cityName: String?,
        timeZoneIdentifier: String?,
        code: String?
    ) {
        self.kindRaw = kindRaw
        self.databaseID = databaseID
        self.customID = customID
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.countryCode = countryCode
        self.countryName = countryName
        self.continentRaw = continentRaw
        self.regionCode = regionCode
        self.regionName = regionName
        self.cityID = cityID
        self.cityName = cityName
        self.timeZoneIdentifier = timeZoneIdentifier
        self.code = code
    }

    init(_ place: PlaceReference) {
        var databaseID: Int?
        var customID: UUID?
        switch place.id {
        case let .database(_, row): databaseID = Int(row)
        case let .custom(uuid): customID = uuid
        }
        self.init(
            kindRaw: place.kind.rawValue,
            databaseID: databaseID,
            customID: customID,
            name: place.name,
            latitude: place.coordinate?.latitude,
            longitude: place.coordinate?.longitude,
            countryCode: place.countryCode,
            countryName: place.countryName,
            continentRaw: place.continent?.rawValue,
            regionCode: place.regionCode,
            regionName: place.regionName,
            cityID: place.cityID.map(Int.init),
            cityName: place.cityName,
            timeZoneIdentifier: place.timeZoneIdentifier,
            code: place.code
        )
    }

    /// Builds the value type. A row that has lost its place identity entirely falls
    /// back to a custom pin keyed on `fallbackID`, which keeps it visible and editable
    /// rather than dropping it.
    func reference(fallbackID: UUID) -> PlaceReference {
        let kind = PlaceKind.decoded(kindRaw)
        let id: PlaceID =
            if let databaseID {
                .database(kind, Int64(databaseID))
            } else {
                .custom(customID ?? fallbackID)
            }
        return PlaceReference(
            id: id,
            kind: kind,
            name: name,
            coordinate: Coordinate.from(latitude, longitude),
            countryCode: countryCode,
            countryName: countryName,
            continent: continentRaw.flatMap(Continent.init(rawValue:)),
            regionCode: regionCode,
            regionName: regionName,
            cityID: cityID.map(Int64.init),
            cityName: cityName,
            timeZoneIdentifier: timeZoneIdentifier,
            code: code
        )
    }
}

public extension StoredVisit {
    var placeReference: PlaceReference {
        PlaceColumns(
            kindRaw: placeKindRaw,
            databaseID: placeDatabaseID,
            customID: placeCustomID,
            name: placeName,
            latitude: latitude,
            longitude: longitude,
            countryCode: countryCode,
            countryName: countryName,
            continentRaw: continentRaw,
            regionCode: regionCode,
            regionName: regionName,
            cityID: cityID,
            cityName: cityName,
            timeZoneIdentifier: timeZoneIdentifier,
            code: placeCode
        ).reference(fallbackID: identifier)
    }

    var asVisit: Visit {
        Visit(
            id: identifier,
            place: placeReference,
            visitType: VisitType(rawValue: visitTypeRaw) ?? .stayed,
            date: FlexibleDate.parse(dateCode) ?? .unknown,
            tripID: trip?.identifier,
            rating: rating,
            notes: notes,
            createdAt: createdAt
        )
    }

    /// Writes a value type into this row. The trip link is set by the store, which
    /// owns the lookup.
    func apply(_ visit: Visit) {
        identifier = visit.id
        visitTypeRaw = visit.visitType.rawValue
        dateCode = visit.date.exportString
        rating = visit.rating
        notes = visit.notes
        apply(place: visit.place)
    }

    func apply(place: PlaceReference) {
        let columns = PlaceColumns(place)
        placeKindRaw = columns.kindRaw
        placeDatabaseID = columns.databaseID
        placeCustomID = columns.customID
        placeName = columns.name
        latitude = columns.latitude
        longitude = columns.longitude
        countryCode = columns.countryCode
        countryName = columns.countryName
        continentRaw = columns.continentRaw
        regionCode = columns.regionCode
        regionName = columns.regionName
        cityID = columns.cityID
        cityName = columns.cityName
        timeZoneIdentifier = columns.timeZoneIdentifier
        placeCode = columns.code
    }
}

public extension StoredLeg {
    internal var originColumns: PlaceColumns {
        PlaceColumns(
            kindRaw: originKindRaw,
            databaseID: originDatabaseID,
            customID: originCustomID,
            name: originName,
            latitude: originLatitude,
            longitude: originLongitude,
            countryCode: originCountryCode,
            countryName: originCountryName,
            continentRaw: originContinentRaw,
            regionCode: originRegionCode,
            regionName: originRegionName,
            cityID: originCityID,
            cityName: originCityName,
            timeZoneIdentifier: originTimeZone,
            code: originCode
        )
    }

    internal var destinationColumns: PlaceColumns {
        PlaceColumns(
            kindRaw: destinationKindRaw,
            databaseID: destinationDatabaseID,
            customID: destinationCustomID,
            name: destinationName,
            latitude: destinationLatitude,
            longitude: destinationLongitude,
            countryCode: destinationCountryCode,
            countryName: destinationCountryName,
            continentRaw: destinationContinentRaw,
            regionCode: destinationRegionCode,
            regionName: destinationRegionName,
            cityID: destinationCityID,
            cityName: destinationCityName,
            timeZoneIdentifier: destinationTimeZone,
            code: destinationCode
        )
    }

    var asLeg: JourneyLeg {
        JourneyLeg(
            id: identifier,
            mode: TravelMode(rawValue: modeRaw) ?? .flight,
            origin: originColumns.reference(fallbackID: identifier),
            // A distinct fallback, so a leg whose two ends both lost their identity
            // does not end up going nowhere.
            destination: destinationColumns
                .reference(fallbackID: Self.destinationFallback(identifier)),
            date: FlexibleDate.parse(dateCode) ?? .unknown,
            purpose: TripPurpose(rawValue: purposeRaw) ?? .leisure,
            storedPathLengthKm: storedPathLengthKm,
            distanceKmOverride: distanceKmOverride,
            durationMinutesOverride: durationMinutesOverride,
            times: LegTimes(
                scheduledDeparture: scheduledDepartureCode.flatMap(LocalDateTime.init(iso:)),
                scheduledArrival: scheduledArrivalCode.flatMap(LocalDateTime.init(iso:)),
                actualDeparture: actualDepartureCode.flatMap(LocalDateTime.init(iso:)),
                actualArrival: actualArrivalCode.flatMap(LocalDateTime.init(iso:))
            ),
            missedConnection: missedConnection,
            routeID: routeID.map(Int64.init),
            routeName: routeName,
            operatorName: operatorName,
            serviceNumber: serviceNumber,
            vehicle: vehicle,
            registration: registration,
            travelClass: travelClass,
            seat: seat,
            rating: rating,
            notes: notes
        )
    }

    /// A stable, distinct UUID derived from the leg's own, by flipping its last byte.
    internal static func destinationFallback(_ identifier: UUID) -> UUID {
        var bytes = identifier.uuid
        bytes.15 ^= 0xFF
        return UUID(uuid: bytes)
    }

    func apply(_ leg: JourneyLeg, sequence: Int) {
        identifier = leg.id
        self.sequence = sequence
        modeRaw = leg.mode.rawValue
        purposeRaw = leg.purpose.rawValue
        dateCode = leg.date.exportString
        storedPathLengthKm = leg.storedPathLengthKm
        distanceKmOverride = leg.distanceKmOverride
        durationMinutesOverride = leg.durationMinutesOverride
        scheduledDepartureCode = leg.times.scheduledDeparture?.iso
        scheduledArrivalCode = leg.times.scheduledArrival?.iso
        actualDepartureCode = leg.times.actualDeparture?.iso
        actualArrivalCode = leg.times.actualArrival?.iso
        missedConnection = leg.missedConnection
        routeID = leg.routeID.map(Int.init)
        routeName = leg.routeName
        operatorName = leg.operatorName
        serviceNumber = leg.serviceNumber
        vehicle = leg.vehicle
        registration = leg.registration
        travelClass = leg.travelClass
        seat = leg.seat
        rating = leg.rating
        notes = leg.notes

        let origin = PlaceColumns(leg.origin)
        originKindRaw = origin.kindRaw
        originDatabaseID = origin.databaseID
        originCustomID = origin.customID
        originName = origin.name
        originLatitude = origin.latitude
        originLongitude = origin.longitude
        originCountryCode = origin.countryCode
        originCountryName = origin.countryName
        originContinentRaw = origin.continentRaw
        originRegionCode = origin.regionCode
        originRegionName = origin.regionName
        originCityID = origin.cityID
        originCityName = origin.cityName
        originTimeZone = origin.timeZoneIdentifier
        originCode = origin.code

        let destination = PlaceColumns(leg.destination)
        destinationKindRaw = destination.kindRaw
        destinationDatabaseID = destination.databaseID
        destinationCustomID = destination.customID
        destinationName = destination.name
        destinationLatitude = destination.latitude
        destinationLongitude = destination.longitude
        destinationCountryCode = destination.countryCode
        destinationCountryName = destination.countryName
        destinationContinentRaw = destination.continentRaw
        destinationRegionCode = destination.regionCode
        destinationRegionName = destination.regionName
        destinationCityID = destination.cityID
        destinationCityName = destination.cityName
        destinationTimeZone = destination.timeZoneIdentifier
        destinationCode = destination.code
    }
}

public extension StoredJourney {
    var asJourney: Journey {
        Journey(
            id: identifier,
            legs: (legs ?? []).sorted { $0.sequence < $1.sequence }.map(\.asLeg),
            tripID: trip?.identifier,
            title: title
        )
    }
}

public extension StoredTrip {
    var asTrip: Trip {
        Trip(id: identifier, name: name, notes: notes, createdAt: createdAt)
    }
}

public extension StoredWishlistItem {
    var asWishlistItem: WishlistItem {
        let place: PlaceReference? = placeKindRaw.map { kindRaw in
            PlaceColumns(
                kindRaw: kindRaw,
                databaseID: placeDatabaseID,
                customID: placeCustomID,
                name: placeName ?? "",
                latitude: latitude,
                longitude: longitude,
                countryCode: countryCode,
                countryName: countryName,
                continentRaw: continentRaw,
                regionCode: regionCode,
                regionName: regionName,
                cityID: cityID,
                cityName: cityName,
                timeZoneIdentifier: timeZoneIdentifier,
                code: placeCode
            ).reference(fallbackID: identifier)
        }
        return WishlistItem(
            id: identifier,
            place: place,
            routeID: routeID.map(Int64.init),
            routeName: routeName,
            notes: notes,
            createdAt: createdAt
        )
    }

    func apply(_ item: WishlistItem) {
        identifier = item.id
        routeID = item.routeID.map(Int.init)
        routeName = item.routeName
        notes = item.notes
        if let created = item.createdAt {
            createdAt = created
        }
        guard let place = item.place else {
            placeKindRaw = nil
            return
        }
        let columns = PlaceColumns(place)
        placeKindRaw = columns.kindRaw
        placeDatabaseID = columns.databaseID
        placeCustomID = columns.customID
        placeName = columns.name
        latitude = columns.latitude
        longitude = columns.longitude
        countryCode = columns.countryCode
        countryName = columns.countryName
        continentRaw = columns.continentRaw
        regionCode = columns.regionCode
        regionName = columns.regionName
        cityID = columns.cityID
        cityName = columns.cityName
        timeZoneIdentifier = columns.timeZoneIdentifier
        placeCode = columns.code
    }
}

extension Coordinate {
    /// Both halves of a coordinate or neither. A row with one of the two is bad data,
    /// not a point on the prime meridian.
    static func from(_ latitude: Double?, _ longitude: Double?) -> Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
