import Foundation

public enum UnitSystem: String, Sendable, Codable, CaseIterable, Identifiable {
    case metric
    case imperial

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .metric: "Kilometres and °C"
        case .imperial: "Miles and °F"
        }
    }

    public var distanceUnitAbbreviation: String {
        switch self {
        case .metric: "km"
        case .imperial: "mi"
        }
    }

    public func distance(fromKilometres kilometres: Double) -> Double {
        switch self {
        case .metric: kilometres
        case .imperial: kilometres / 1.609_344
        }
    }

    public func temperature(fromCelsius celsius: Double) -> Double {
        switch self {
        case .metric: celsius
        case .imperial: celsius * 9 / 5 + 32
        }
    }
}

/// Which places count as a country when "% of the world" is worked out.
///
/// There is no single right answer, which is why this is a choice the user makes rather
/// than a constant (Q-4, decision D-6). Someone who has been to Greenland, Hong Kong
/// and Puerto Rico may reasonably count them; the UN does not. Offering the lists and
/// naming what each one is beats picking one quietly and being wrong for half the
/// users.
///
/// The counts come from the place database, which derives UN membership from Wikidata
/// and the territory list from ISO 3166-1 (see `PlaceDatabase.countryListCounts()`).
/// `fallbackCount` is only used when a database is too old to carry them.
public enum CountryList: String, Sendable, Codable, CaseIterable, Identifiable {
    /// The 193 member states of the United Nations.
    case unMembers
    /// The 193 members plus the two permanent observer states, the Holy See and
    /// Palestine.
    case unMembersAndObservers
    /// Every entry with an ISO 3166-1 code: sovereign states, plus dependencies and
    /// territories such as Greenland, Hong Kong and Bermuda.
    case allCountriesAndTerritories

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .unMembers: "UN member states"
        case .unMembersAndObservers: "UN members and observers"
        case .allCountriesAndTerritories: "Countries and territories"
        }
    }

    public var explanation: String {
        switch self {
        case .unMembers:
            "The strictest list, and the one most travel counts use."
        case .unMembersAndObservers:
            "Adds the Holy See and Palestine, which hold permanent observer status."
        case .allCountriesAndTerritories:
            "Every place with its own ISO country code, so Greenland, Hong Kong and "
                + "Bermuda each count separately."
        }
    }

    /// The `meta` key the pipeline writes this list's count to.
    public var metaKey: String {
        switch self {
        case .unMembers: "country_count_un_members"
        case .unMembersAndObservers: "country_count_un_members_and_observers"
        case .allCountriesAndTerritories: "country_count_all"
        }
    }

    /// Used only when the database does not carry a count for this list.
    public var fallbackCount: Int {
        switch self {
        case .unMembers: 193
        case .unMembersAndObservers: 195
        case .allCountriesAndTerritories: 249
        }
    }
}

/// What counts, and in what units.
///
/// Every statistic takes these rather than reading a global, so a stat screen can show
/// the same number under two rule sets and tests can set the rules explicitly
/// (R-MODEL-7, R-CALC-1, R-CALC-4).
public struct CountingRules: Hashable, Sendable, Codable {
    /// Count visits marked "passed through" towards coverage.
    public var includePassedThrough: Bool
    /// Count airport and station layovers towards coverage.
    public var includeLayovers: Bool
    /// Include commute legs in distance and journey stats (Q-15).
    public var includeCommutes: Bool
    public var unitSystem: UnitSystem

    /// Which list of countries the user has chosen to measure against (Q-4).
    public var countryList: CountryList

    /// How many countries "% of the world" is measured against.
    ///
    /// Derived from `countryList`, but stored rather than computed because the real
    /// count lives in the place database: the app reads it with
    /// `PlaceDatabase.countryListCounts()` and calls ``applyCountryCounts(_:)``. Until
    /// then it holds the chosen list's `fallbackCount`, so a stat is never divided by
    /// zero or by a number from nowhere.
    public var worldCountryCount: Int

    public static let `default` = CountingRules()

    public init(
        includePassedThrough: Bool = false,
        includeLayovers: Bool = false,
        includeCommutes: Bool = false,
        unitSystem: UnitSystem = .metric,
        countryList: CountryList = .unMembers,
        worldCountryCount: Int? = nil
    ) {
        self.includePassedThrough = includePassedThrough
        self.includeLayovers = includeLayovers
        self.includeCommutes = includeCommutes
        self.unitSystem = unitSystem
        self.countryList = countryList
        self.worldCountryCount = max(1, worldCountryCount ?? countryList.fallbackCount)
    }

    /// Points `worldCountryCount` at the chosen list's real count from the database.
    ///
    /// Call it when the database info loads and whenever the user picks a different
    /// list, so the denominator and the label on screen never disagree.
    public mutating func applyCountryCounts(_ counts: [CountryList: Int]) {
        if let count = counts[countryList] {
            worldCountryCount = max(1, count)
        }
    }

    public func countsTowardsCoverage(_ visitType: VisitType) -> Bool {
        switch visitType {
        case .stayed, .dayTrip: true
        case .passedThrough: includePassedThrough
        case .layover: includeLayovers
        }
    }

    public func countsInStats(_ purpose: TripPurpose) -> Bool {
        purpose == .commute ? includeCommutes : true
    }
}
