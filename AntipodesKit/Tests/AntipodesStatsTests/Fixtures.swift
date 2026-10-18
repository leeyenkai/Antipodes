import AntipodesCore
import Foundation

/// A small hand-built log with known contents, so every expected value in these tests
/// can be worked out on paper.
enum Fixtures {
    static func country(
        _ iso2: String,
        _ name: String,
        _ continent: Continent,
        id: Int64
    ) -> PlaceReference {
        PlaceReference(
            id: .database(.country, id),
            kind: .country,
            name: name,
            coordinate: Coordinate(latitude: 0, longitude: 0),
            countryCode: iso2,
            countryName: name,
            continent: continent
        )
    }

    static func city(
        _ name: String,
        _ iso2: String,
        _ countryName: String,
        _ continent: Continent,
        id: Int64,
        latitude: Double,
        longitude: Double,
        region: String? = nil
    ) -> PlaceReference {
        PlaceReference(
            id: .database(.city, id),
            kind: .city,
            name: name,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            countryCode: iso2,
            countryName: countryName,
            continent: continent,
            regionCode: region,
            cityID: id,
            cityName: name
        )
    }

    static func landmark(
        _ name: String,
        _ iso2: String,
        _ countryName: String,
        _ continent: Continent,
        id: Int64,
        cityID: Int64,
        cityName: String,
        latitude: Double,
        longitude: Double,
        region: String? = nil
    ) -> PlaceReference {
        PlaceReference(
            id: .database(.landmark, id),
            kind: .landmark,
            name: name,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            countryCode: iso2,
            countryName: countryName,
            continent: continent,
            regionCode: region,
            cityID: cityID,
            cityName: cityName
        )
    }

    static func airport(
        _ code: String,
        _ iso2: String,
        _ countryName: String,
        _ continent: Continent,
        id: Int64,
        latitude: Double,
        longitude: Double
    ) -> PlaceReference {
        PlaceReference(
            id: .database(.airport, id),
            kind: .airport,
            name: code,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            countryCode: iso2,
            countryName: countryName,
            continent: continent
        )
    }

    /// Real coordinates, so distances can be checked against published figures.
    static let osl = airport(
        "OSL",
        "NO",
        "Norway",
        .europe,
        id: 1,
        latitude: 60.1939,
        longitude: 11.1004
    )
    static let jfk = airport(
        "JFK",
        "US",
        "United States",
        .northAmerica,
        id: 2,
        latitude: 40.6413,
        longitude: -73.7781
    )
    static let lhr = airport(
        "LHR",
        "GB",
        "United Kingdom",
        .europe,
        id: 3,
        latitude: 51.4700,
        longitude: -0.4543
    )
    static let syd = airport(
        "SYD",
        "AU",
        "Australia",
        .oceania,
        id: 4,
        latitude: -33.9399,
        longitude: 151.1753
    )

    static let oslo = city(
        "Oslo",
        "NO",
        "Norway",
        .europe,
        id: 10,
        latitude: 59.9139,
        longitude: 10.7522,
        region: "NO-03"
    )
    static let bergen = city(
        "Bergen",
        "NO",
        "Norway",
        .europe,
        id: 11,
        latitude: 60.3913,
        longitude: 5.3221,
        region: "NO-46"
    )
    static let rome = city(
        "Rome",
        "IT",
        "Italy",
        .europe,
        id: 12,
        latitude: 41.9028,
        longitude: 12.4964,
        region: "IT-62"
    )
    static let tokyo = city(
        "Tokyo",
        "JP",
        "Japan",
        .asia,
        id: 13,
        latitude: 35.6762,
        longitude: 139.6503,
        region: "JP-13"
    )
    static let longyearbyen = city(
        "Longyearbyen",
        "SJ",
        "Svalbard",
        .europe,
        id: 14,
        latitude: 78.2232,
        longitude: 15.6267
    )

    static let colosseum = landmark(
        "Colosseum",
        "IT",
        "Italy",
        .europe,
        id: 20,
        cityID: 12,
        cityName: "Rome",
        latitude: 41.8902,
        longitude: 12.4922,
        region: "IT-62"
    )

    static func visit(
        _ place: PlaceReference,
        _ type: VisitType = .stayed,
        _ date: FlexibleDate = .year(2024),
        trip: UUID? = nil
    ) -> Visit {
        Visit(place: place, visitType: type, date: date, tripID: trip)
    }

    static func flight(
        _ from: PlaceReference,
        _ to: PlaceReference,
        purpose: TripPurpose = .leisure,
        airline: String? = nil,
        aircraft: String? = nil
    ) -> JourneyLeg {
        JourneyLeg(
            mode: .flight,
            origin: from,
            destination: to,
            date: .year(2024),
            purpose: purpose,
            operatorName: airline,
            vehicle: aircraft
        )
    }

    static func railLeg(
        _ from: PlaceReference,
        _ to: PlaceReference,
        storedPathLengthKm: Double? = nil,
        purpose: TripPurpose = .leisure
    ) -> JourneyLeg {
        JourneyLeg(
            mode: .rail,
            origin: from,
            destination: to,
            date: .year(2024),
            purpose: purpose,
            storedPathLengthKm: storedPathLengthKm
        )
    }
}
