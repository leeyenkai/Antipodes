import Foundation

/// Attributes of one bundled place, read from the place database for the statistics
/// that need more than a name and a coordinate (§7, "Place attributes").
///
/// Every field is optional because the database leaves unknowns empty rather than
/// guessing (R-DB-2). A stat that reads one of these reports how many places it had a
/// value for, so "average landmark age" can say it rests on 42 of 50 landmarks.
public struct PlaceFacts: Hashable, Sendable, Codable {
    public var population: Int?
    public var elevationM: Double?
    public var timeZoneIdentifier: String?
    /// Year built, negative for BC. Landmarks only.
    public var yearBuilt: Int?
    /// "5th century BC", where the year is known only that well (R-DB-3). Landmarks only.
    public var era: String?
    public var heightM: Double?
    /// Listed as a UNESCO World Heritage Site in its own right. `false` is not proof of
    /// the opposite: the Colosseum is part of a listed site without carrying the
    /// designation itself.
    public var isUNESCO: Bool
    /// Theme tags from the curated taxonomy (R-DB-1). Landmarks only.
    public var themes: [String]
    /// A national capital, as GeoNames marks it (PPLC).
    public var isCapital: Bool
    /// What kind of landmark it is, e.g. "national park", where known.
    public var landmarkKind: String?
    /// Mean temperature of each month, January first, °C: the 1991-2020 normal at the
    /// place (R-CALC-2). `nil` where the climate grid had no land within reach.
    public var monthlyMeanTemperatureC: [Double]?
    /// The Köppen-Geiger climate zone those normals make, such as "Cfb".
    public var koppen: String?

    public init(
        population: Int? = nil,
        elevationM: Double? = nil,
        timeZoneIdentifier: String? = nil,
        yearBuilt: Int? = nil,
        era: String? = nil,
        heightM: Double? = nil,
        isUNESCO: Bool = false,
        themes: [String] = [],
        isCapital: Bool = false,
        landmarkKind: String? = nil,
        monthlyMeanTemperatureC: [Double]? = nil,
        koppen: String? = nil
    ) {
        self.population = population
        self.elevationM = elevationM
        self.timeZoneIdentifier = timeZoneIdentifier
        self.yearBuilt = yearBuilt
        self.era = era
        self.heightM = heightM
        self.isUNESCO = isUNESCO
        self.themes = themes
        self.isCapital = isCapital
        self.landmarkKind = landmarkKind
        self.monthlyMeanTemperatureC = monthlyMeanTemperatureC
        self.koppen = koppen
    }

    /// The years an era covers, read from the database's own wording: century *n* is
    /// the hundred years from (n − 1) × 100, so the 15th century is 1400–1499 and the
    /// 5th century BC 500–401 BC. `nil` for anything else.
    public var eraYears: ClosedRange<Int>? {
        guard let era else { return nil }
        let words = era.split(separator: " ")
        guard words.count >= 2, let number = Int(words[0].prefix { $0.isNumber }), number > 0
        else { return nil }
        let size = switch words[1] {
        case "century": 100
        case "millennium": 1000
        default: 0
        }
        guard size > 0 else { return nil }
        let start = (number - 1) * size
        let end = number * size - 1
        return words.last == "BC" ? -(end + 1) ... -(start + 1) : start ... end
    }

    /// The mean of the twelve monthly normals.
    public var annualMeanTemperatureC: Double? {
        guard let months = monthlyMeanTemperatureC, months.count == 12 else { return nil }
        return months.reduce(0, +) / 12
    }
}

/// Facts about a country, for the languages, currencies and capitals stats.
public struct CountryFacts: Hashable, Sendable, Codable, Identifiable {
    public var id: String {
        code
    }

    /// ISO 3166-1 alpha-2.
    public let code: String
    public let name: String
    public let continent: Continent?
    public let capitalName: String?
    public let population: Int?
    public let areaKm2: Double?
    /// ISO 4217, e.g. `NOK`.
    public let currencyCode: String?
    /// Language codes in GeoNames' order of importance, e.g. `["nb", "no", "nn"]`.
    public let languageCodes: [String]
    public let isUNMember: Bool
    public let isUNObserver: Bool

    public init(
        code: String,
        name: String,
        continent: Continent? = nil,
        capitalName: String? = nil,
        population: Int? = nil,
        areaKm2: Double? = nil,
        currencyCode: String? = nil,
        languageCodes: [String] = [],
        isUNMember: Bool = false,
        isUNObserver: Bool = false
    ) {
        self.code = code.uppercased()
        self.name = name
        self.continent = continent
        self.capitalName = capitalName
        self.population = population
        self.areaKm2 = areaKm2
        self.currencyCode = currencyCode
        self.languageCodes = languageCodes
        self.isUNMember = isUNMember
        self.isUNObserver = isUNObserver
    }

    /// The main language, without a region suffix: GeoNames writes `en-GB`, and two
    /// English-speaking countries should count as one language.
    public var primaryLanguage: String? {
        languageCodes.first.map { $0.split(separator: "-").first.map(String.init) ?? $0 }
    }

    /// Whether this country is on the list the user has chosen to count (Q-4).
    public func isCounted(on list: CountryList) -> Bool {
        switch list {
        case .unMembers: isUNMember
        case .unMembersAndObservers: isUNMember || isUNObserver
        case .allCountriesAndTerritories: true
        }
    }
}

/// One tag from the landmark theme taxonomy (R-DB-1, Q-6).
public struct ThemeDefinition: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let label: String
    public let description: String?

    public init(id: String, label: String, description: String? = nil) {
        self.id = id
        self.label = label
        self.description = description
    }
}

/// Everything the statistics engine may know about places beyond the log itself.
///
/// The engine stays a pure function: the app reads these facts out of the place
/// database and hands them over, and a test builds one by hand (decision D-2). An empty
/// gazetteer is valid — every attribute stat then reports that it had nothing to use.
public struct Gazetteer: Hashable, Sendable {
    public var places: [PlaceID: PlaceFacts]
    public var countries: [String: CountryFacts]
    public var themes: [ThemeDefinition]

    public static let empty = Gazetteer()

    public init(
        places: [PlaceID: PlaceFacts] = [:],
        countries: [String: CountryFacts] = [:],
        themes: [ThemeDefinition] = []
    ) {
        self.places = places
        self.countries = countries
        self.themes = themes
    }

    public func facts(for id: PlaceID) -> PlaceFacts? {
        places[id]
    }

    public func country(_ code: String?) -> CountryFacts? {
        code.flatMap { countries[$0.uppercased()] }
    }

    public func themeLabel(_ id: String) -> String {
        themes.first { $0.id == id }?.label ?? id
    }
}
