import Foundation

public enum PlaceKind: String, Sendable, Codable, CaseIterable, Identifiable {
    case country
    case region
    case city
    case landmark
    case airport
    case route
    /// A pin the user dropped for something not in the database (R-LOG-5).
    case custom

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .country: "Country"
        case .region: "Region"
        case .city: "City"
        case .landmark: "Landmark"
        case .airport: "Airport"
        case .route: "Route"
        case .custom: "Custom pin"
        }
    }

    public var symbolName: String {
        switch self {
        case .country: "flag"
        case .region: "map"
        case .city: "building.2"
        case .landmark: "building.columns"
        case .airport: "airplane.departure"
        case .route: "point.topleft.down.to.point.bottomright.curvepath"
        case .custom: "mappin.and.ellipse"
        }
    }
}

/// Identity of a place, keeping the read-only database and the user's own pins apart.
///
/// Database rows are shared by every user and are stable across database versions.
/// Custom pins belong to one user and live in their SwiftData store (R-MODEL-5).
public enum PlaceID: Hashable, Sendable, Codable, CustomStringConvertible {
    case database(PlaceKind, Int64)
    case custom(UUID)

    public var description: String {
        switch self {
        case let .database(kind, row): "\(kind.rawValue):\(row)"
        case let .custom(uuid): "custom:\(uuid.uuidString)"
        }
    }
}

/// A place as the user's log refers to it: enough denormalised context for stats to
/// run without opening the place database.
///
/// The hierarchy fields carry the implication chain in R-MODEL-6 — a landmark knows
/// its city, region and country, so logging it counts all of them. Nothing wider than
/// that chain is implied.
public struct PlaceReference: Hashable, Sendable, Codable, Identifiable {
    public var id: PlaceID
    public var kind: PlaceKind
    public var name: String
    public var coordinate: Coordinate?

    /// ISO 3166-1 alpha-2, uppercased. `nil` only where geocoding has not resolved
    /// yet; a custom pin gets one from bundled borders (R-LOG-5).
    public var countryCode: String?
    public var countryName: String?
    public var continent: Continent?

    /// Region identity within the country, e.g. `US-CA`. Counted by the regions stat.
    public var regionCode: String?
    public var regionName: String?

    /// The city a landmark or airport belongs to, so logging it implies the city.
    public var cityID: Int64?
    public var cityName: String?

    public init(
        id: PlaceID,
        kind: PlaceKind,
        name: String,
        coordinate: Coordinate? = nil,
        countryCode: String? = nil,
        countryName: String? = nil,
        continent: Continent? = nil,
        regionCode: String? = nil,
        regionName: String? = nil,
        cityID: Int64? = nil,
        cityName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.coordinate = coordinate
        self.countryCode = countryCode?.uppercased()
        self.countryName = countryName
        self.continent = continent
        self.regionCode = regionCode
        self.regionName = regionName
        self.cityID = cityID
        self.cityName = cityName
    }

    /// Every city this place implies, as database identity. A city implies itself; a
    /// landmark or airport implies its parent city (R-MODEL-6).
    public var impliedCityID: Int64? {
        if case let .database(.city, row) = id {
            return row
        }
        return cityID
    }

    /// A region identity namespaced by country, so `CA` in Canada and California never
    /// collide.
    public var qualifiedRegionCode: String? {
        guard let regionCode else { return nil }
        if regionCode.contains("-") {
            return regionCode
        }
        guard let countryCode else { return regionCode }
        return "\(countryCode)-\(regionCode)"
    }
}
