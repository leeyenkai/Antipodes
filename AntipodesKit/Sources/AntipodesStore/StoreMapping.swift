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

public extension StoredVisit {
    /// Builds the value type. A row that has lost its place identity entirely falls
    /// back to a custom pin keyed on the visit, which keeps it visible and editable
    /// rather than dropping it.
    var placeReference: PlaceReference {
        let kind = PlaceKind.decoded(placeKindRaw)
        let id: PlaceID =
            if let databaseID = placeDatabaseID {
                .database(kind, Int64(databaseID))
            } else {
                .custom(placeCustomID ?? identifier)
            }

        return PlaceReference(
            id: id,
            kind: kind,
            name: placeName,
            coordinate: Coordinate.from(latitude, longitude),
            countryCode: countryCode,
            countryName: countryName,
            continent: continentRaw.flatMap(Continent.init(rawValue:)),
            regionCode: regionCode,
            regionName: regionName,
            cityID: cityID.map(Int64.init),
            cityName: cityName
        )
    }

    var asVisit: Visit {
        Visit(
            id: identifier,
            place: placeReference,
            visitType: VisitType(rawValue: visitTypeRaw) ?? .stayed,
            date: FlexibleDate.parse(dateCode) ?? .unknown,
            tripID: trip?.identifier,
            rating: rating,
            notes: notes
        )
    }

    /// Writes a value type into this row.
    func apply(_ visit: Visit) {
        identifier = visit.id
        visitTypeRaw = visit.visitType.rawValue
        dateCode = visit.date.exportString
        rating = visit.rating
        notes = visit.notes
        apply(place: visit.place)
    }

    func apply(place: PlaceReference) {
        placeKindRaw = place.kind.rawValue
        switch place.id {
        case let .database(_, row):
            placeDatabaseID = Int(row)
            placeCustomID = nil
        case let .custom(uuid):
            placeDatabaseID = nil
            placeCustomID = uuid
        }
        placeName = place.name
        latitude = place.coordinate?.latitude
        longitude = place.coordinate?.longitude
        countryCode = place.countryCode
        countryName = place.countryName
        continentRaw = place.continent?.rawValue
        regionCode = place.regionCode
        regionName = place.regionName
        cityID = place.cityID.map(Int.init)
        cityName = place.cityName
    }
}

public extension StoredLeg {
    var asLeg: JourneyLeg {
        JourneyLeg(
            id: identifier,
            mode: TravelMode(rawValue: modeRaw) ?? .flight,
            origin: PlaceReference(
                id: originDatabaseID.map { PlaceID.database(.decoded(originKindRaw), Int64($0)) }
                    ?? .custom(originCustomID ?? identifier),
                kind: .decoded(originKindRaw),
                name: originName,
                coordinate: Coordinate.from(originLatitude, originLongitude),
                countryCode: originCountryCode,
                countryName: originCountryName,
                continent: originContinentRaw.flatMap(Continent.init(rawValue:)),
                cityID: originCityID.map(Int64.init),
                cityName: originCityName
            ),
            destination: PlaceReference(
                id: destinationDatabaseID
                    .map { PlaceID.database(.decoded(destinationKindRaw), Int64($0)) }
                    ?? .custom(destinationCustomID ?? identifier),
                kind: .decoded(destinationKindRaw),
                name: destinationName,
                coordinate: Coordinate.from(destinationLatitude, destinationLongitude),
                countryCode: destinationCountryCode,
                countryName: destinationCountryName,
                continent: destinationContinentRaw.flatMap(Continent.init(rawValue:)),
                cityID: destinationCityID.map(Int64.init),
                cityName: destinationCityName
            ),
            date: FlexibleDate.parse(dateCode) ?? .unknown,
            purpose: TripPurpose(rawValue: purposeRaw) ?? .leisure,
            storedPathLengthKm: storedPathLengthKm,
            distanceKmOverride: distanceKmOverride,
            durationMinutesOverride: durationMinutesOverride,
            operatorName: operatorName,
            serviceNumber: serviceNumber,
            vehicle: vehicle,
            travelClass: travelClass,
            seat: seat,
            rating: rating,
            notes: notes
        )
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
        operatorName = leg.operatorName
        serviceNumber = leg.serviceNumber
        vehicle = leg.vehicle
        travelClass = leg.travelClass
        seat = leg.seat
        rating = leg.rating
        notes = leg.notes

        originKindRaw = leg.origin.kind.rawValue
        if case let .database(_, row) = leg.origin.id {
            originDatabaseID = Int(row)
            originCustomID = nil
        } else if case let .custom(uuid) = leg.origin.id {
            originDatabaseID = nil
            originCustomID = uuid
        }
        originName = leg.origin.name
        originLatitude = leg.origin.coordinate?.latitude
        originLongitude = leg.origin.coordinate?.longitude
        originCountryCode = leg.origin.countryCode
        originCountryName = leg.origin.countryName
        originContinentRaw = leg.origin.continent?.rawValue
        originCityID = leg.origin.cityID.map(Int.init)
        originCityName = leg.origin.cityName

        destinationKindRaw = leg.destination.kind.rawValue
        if case let .database(_, row) = leg.destination.id {
            destinationDatabaseID = Int(row)
            destinationCustomID = nil
        } else if case let .custom(uuid) = leg.destination.id {
            destinationDatabaseID = nil
            destinationCustomID = uuid
        }
        destinationName = leg.destination.name
        destinationLatitude = leg.destination.coordinate?.latitude
        destinationLongitude = leg.destination.coordinate?.longitude
        destinationCountryCode = leg.destination.countryCode
        destinationCountryName = leg.destination.countryName
        destinationContinentRaw = leg.destination.continent?.rawValue
        destinationCityID = leg.destination.cityID.map(Int.init)
        destinationCityName = leg.destination.cityName
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
        Trip(id: identifier, name: name, notes: notes)
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
