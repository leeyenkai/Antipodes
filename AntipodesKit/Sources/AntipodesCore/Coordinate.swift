import Foundation

/// A point on the Earth's surface in decimal degrees.
///
/// Latitude is clamped to [-90, 90] and longitude normalised to [-180, 180) on
/// creation, so every `Coordinate` in the app is already valid. Nothing downstream
/// needs to re-check.
public struct Coordinate: Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = min(90, max(-90, latitude))
        self.longitude = Coordinate.normalisedLongitude(longitude)
    }

    /// Fails rather than clamps. Use when parsing data that should already be valid,
    /// so bad rows are visible instead of silently moved to a pole.
    public init?(validating latitude: Double, _ longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude)
        else { return nil }
        self.init(latitude: latitude, longitude: longitude)
    }

    static func normalisedLongitude(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        var longitude = value.truncatingRemainder(dividingBy: 360)
        if longitude >= 180 {
            longitude -= 360
        }
        if longitude < -180 {
            longitude += 360
        }
        return longitude == -0.0 ? 0 : longitude
    }

    public var latitudeRadians: Double {
        latitude * .pi / 180
    }

    public var longitudeRadians: Double {
        longitude * .pi / 180
    }

    /// The point on exactly the opposite side of the globe.
    ///
    /// The app is named after this, and it is a shipped statistic ("your antipode").
    public var antipode: Coordinate {
        Coordinate(latitude: -latitude, longitude: longitude + 180)
    }

    /// The point as a unit vector from the Earth's centre, for comparing directions
    /// without trigonometry: two points are further apart the smaller their dot product.
    public var unitVector: (x: Double, y: Double, z: Double) {
        let cosLatitude = cos(latitudeRadians)
        return (
            cosLatitude * cos(longitudeRadians),
            cosLatitude * sin(longitudeRadians),
            sin(latitudeRadians)
        )
    }

    public var hemisphere: Hemisphere {
        latitude >= 0 ? .northern : .southern
    }

    /// Latitude circles the app awards achievements for crossing (R-ACH-2).
    public var isNorthOfArcticCircle: Bool {
        latitude >= 66.5635
    }

    public var isSouthOfAntarcticCircle: Bool {
        latitude <= -66.5635
    }

    public var isWithinTropics: Bool {
        abs(latitude) <= 23.4365
    }
}

public enum Hemisphere: String, Sendable, Codable, CaseIterable {
    case northern, southern
}

public enum Continent: String, Sendable, Codable, CaseIterable, Comparable {
    case africa
    case antarctica
    case asia
    case europe
    case northAmerica
    case oceania
    case southAmerica

    public var displayName: String {
        switch self {
        case .africa: "Africa"
        case .antarctica: "Antarctica"
        case .asia: "Asia"
        case .europe: "Europe"
        case .northAmerica: "North America"
        case .oceania: "Oceania"
        case .southAmerica: "South America"
        }
    }

    /// The seven-continent model, which is what "all seven continents" means in the
    /// achievement (R-ACH-2) and what the continent coverage stat counts against.
    public static var allSeven: [Continent] {
        allCases
    }

    public static func < (lhs: Continent, rhs: Continent) -> Bool {
        lhs.displayName < rhs.displayName
    }
}

extension Coordinate {
    private enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }

    /// A decoded coordinate is checked like a parsed one: a backup holding NaN or a
    /// latitude of 400 fails to read rather than drawing a pin nowhere.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let coordinate = try Coordinate(
            validating: container.decode(Double.self, forKey: .latitude),
            container.decode(Double.self, forKey: .longitude)
        ) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not a point on the Earth"
            ))
        }
        self = coordinate
    }
}
