import Foundation

/// A curated collection the user can work through, such as the New 7 Wonders
/// (R-WISH-2). Defined in the place database so new ones arrive with an update
/// (R-DB-6).
public struct CollectionDefinition: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    /// An SF Symbol name.
    public let symbol: String?
    /// Each member as a full reference, so progress can follow the implication chain —
    /// a member city is ticked off by a landmark inside it (R-MODEL-6).
    public let members: [PlaceReference]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        symbol: String? = nil,
        members: [PlaceReference]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.symbol = symbol
        self.members = members
    }
}

/// The rule an achievement is evaluated by (R-ACH-1).
///
/// Each case's raw value is the `rule` column in the database. A definition whose rule
/// this build does not know is skipped rather than guessed at, so a database update can
/// add new thresholds for known rules without an app release.
public enum AchievementRule: String, Sendable, Codable, CaseIterable {
    case countries
    case continents
    case regions
    case cities
    case capitals
    case landmarks
    case unesco
    case airports
    case flights
    case trips
    case distance
    case modes
    case collectionComplete = "collection-complete"
    case collectionCount = "collection-count"
    case unescoInOneTrip = "unesco-in-one-trip"
    case overnightTrain = "overnight-train"
    case crossedEquator = "crossed-equator"
    case arcticCircle = "arctic-circle"
    case antarcticCircle = "antarctic-circle"
    case antipodes
}

/// A rung on a ladder of achievements (R-ACH-3).
public enum AchievementTier: String, Sendable, Codable, CaseIterable, Comparable {
    case bronze
    case silver
    case gold
    case platinum

    public var displayName: String {
        rawValue.capitalized
    }

    private var rank: Int {
        switch self {
        case .bronze: 0
        case .silver: 1
        case .gold: 2
        case .platinum: 3
        }
    }

    public static func < (lhs: AchievementTier, rhs: AchievementTier) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct AchievementDefinition: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let symbol: String?
    /// `nil` when the database names a rule this build does not know.
    public let rule: AchievementRule?
    public let threshold: Double?
    public let parameter: String?
    public let tier: AchievementTier?
    public let sortOrder: Int

    public init(
        id: String,
        name: String,
        description: String,
        symbol: String? = nil,
        rule: AchievementRule?,
        threshold: Double? = nil,
        parameter: String? = nil,
        tier: AchievementTier? = nil,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.symbol = symbol
        self.rule = rule
        self.threshold = threshold
        self.parameter = parameter
        self.tier = tier
        self.sortOrder = sortOrder
    }
}

/// A famous route from the catalogue (§6, R-JLOG-3).
public struct RouteInfo: Hashable, Sendable, Codable, Identifiable {
    public let id: Int64
    public let name: String
    public let mode: TravelMode
    public let startName: String?
    public let endName: String?
    /// Where the route starts and ends, where those are bundled places. `nil` when the
    /// end of the line is too small to be in the bundled city set; the user then picks
    /// where they got on or off.
    public let start: PlaceReference?
    public let end: PlaceReference?
    public let countryCodes: [String]
    /// The route's length along its real path, where the catalogue records one.
    public let lengthKm: Double?
    public let typicalDurationMinutes: Int?
    public let highestPointM: Double?

    public init(
        id: Int64,
        name: String,
        mode: TravelMode,
        startName: String? = nil,
        endName: String? = nil,
        start: PlaceReference? = nil,
        end: PlaceReference? = nil,
        countryCodes: [String] = [],
        lengthKm: Double? = nil,
        typicalDurationMinutes: Int? = nil,
        highestPointM: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.startName = startName
        self.endName = endName
        self.start = start
        self.end = end
        self.countryCodes = countryCodes
        self.lengthKm = lengthKm
        self.typicalDurationMinutes = typicalDurationMinutes
        self.highestPointM = highestPointM
    }
}

/// Whether a carbon factor is per passenger or per vehicle.
public enum EmissionBasis: String, Sendable, Codable {
    /// Per passenger-km: the traveller's own share.
    case passenger
    /// Per vehicle-km: the whole car's emissions, however many people share it.
    case vehicle
}

/// One published carbon factor (R-CO2-1).
public struct EmissionFactor: Hashable, Sendable, Codable {
    public let mode: TravelMode
    /// Empty for the mode's default, otherwise a ``EmissionFactorTable/classKey(for:mode:)``.
    public let travelClass: String
    public let kgCO2ePerKm: Double
    public let basis: EmissionBasis
    /// The publisher's own description of the factor.
    public let label: String
    public let year: Int

    public init(
        mode: TravelMode,
        travelClass: String = "",
        kgCO2ePerKm: Double,
        basis: EmissionBasis,
        label: String,
        year: Int
    ) {
        self.mode = mode
        self.travelClass = travelClass
        self.kgCO2ePerKm = kgCO2ePerKm
        self.basis = basis
        self.label = label
        self.year = year
    }
}

/// Every carbon factor the database carries, and the rule for picking one for a leg.
public struct EmissionFactorTable: Hashable, Sendable {
    public let factors: [EmissionFactor]
    /// The publisher, for the "estimate, source and year" label every carbon figure
    /// carries (R-CO2-3).
    public let sourceName: String

    public static let empty = EmissionFactorTable(factors: [], sourceName: "")

    public init(factors: [EmissionFactor], sourceName: String) {
        self.factors = factors
        self.sourceName = sourceName
    }

    public var isEmpty: Bool {
        factors.isEmpty
    }

    /// The year of the factor set, where every factor agrees on one.
    public var year: Int? {
        let years = Set(factors.map(\.year))
        return years.count == 1 ? years.first : years.max()
    }

    /// The factor for a mode and a class, falling back to the mode's default where the
    /// class has no factor of its own. Human-powered travel has no direct emissions and
    /// is answered with zero rather than looked up.
    public func factor(for mode: TravelMode, travelClass: String?) -> EmissionFactor? {
        if mode == .humanPowered {
            return EmissionFactor(
                mode: mode,
                kgCO2ePerKm: 0,
                basis: .passenger,
                label: "No direct emissions",
                year: year ?? 0
            )
        }
        let key = Self.classKey(for: travelClass, mode: mode)
        if let key, let match = factors.first(where: { $0.mode == mode && $0.travelClass == key }) {
            return match
        }
        return factors.first { $0.mode == mode && $0.travelClass.isEmpty }
    }

    /// Maps the free-text class a user typed onto the class keys the factors use.
    ///
    /// "Business", "business class" and "Club World (business)" all map to `business`;
    /// anything unrecognised falls back to the mode's average rather than guessing.
    public static func classKey(for travelClass: String?, mode: TravelMode) -> String? {
        guard let text = travelClass?.lowercased(), !text.isEmpty else { return nil }
        switch mode {
        case .flight:
            if text.contains("first") {
                return "first"
            }
            if text.contains("business") || text.contains("club") {
                return "business"
            }
            if text.contains("premium") {
                return "premium"
            }
            if text.contains("economy") || text.contains("coach") {
                return "economy"
            }
            return nil
        case .ferry:
            if text.contains("foot") {
                return "foot"
            }
            if text.contains("car") || text.contains("vehicle") {
                return "car"
            }
            return nil
        case .roadTrip:
            if text.contains("motorbike") || text.contains("motorcycle") {
                return "motorbike"
            }
            return nil
        case .rail, .cityTransit, .coach, .humanPowered, .cableAndMountain:
            return nil
        }
    }
}
