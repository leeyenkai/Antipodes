import AntipodesCore
import Foundation

/// One theme's share of everything visited.
public struct ThemeShare: Hashable, Sendable, Identifiable {
    public var id: String {
        theme
    }

    public let theme: String
    public let label: String
    /// Landmarks' worth of this theme: a landmark tagged with two themes gives half to
    /// each, so every landmark weighs the same however it was tagged.
    public let weight: Double
    /// Share of the total, in 0...1.
    public let share: Double
}

/// A broad span of history, for "spread across historical eras" (§7).
public enum HistoricalEra: String, Sendable, CaseIterable, Identifiable, Comparable {
    case ancient
    case medieval
    case earlyModern
    case industrial
    case modern
    case contemporary

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .ancient: "Ancient"
        case .medieval: "Medieval"
        case .earlyModern: "Early modern"
        case .industrial: "Industrial age"
        case .modern: "20th century"
        case .contemporary: "21st century"
        }
    }

    public var span: String {
        switch self {
        case .ancient: "before 500"
        case .medieval: "500–1499"
        case .earlyModern: "1500–1799"
        case .industrial: "1800–1899"
        case .modern: "1900–1999"
        case .contemporary: "2000 onwards"
        }
    }

    /// The era a year built falls in. The boundaries are the conventional ones and the
    /// same as the theme taxonomy's own descriptions of ancient and medieval.
    public static func containing(year: Int) -> HistoricalEra {
        switch year {
        case ..<500: .ancient
        case 500 ..< 1500: .medieval
        case 1500 ..< 1800: .earlyModern
        case 1800 ..< 1900: .industrial
        case 1900 ..< 2000: .modern
        default: .contemporary
        }
    }

    public static func < (lhs: HistoricalEra, rhs: HistoricalEra) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    /// A landmark's era: by its year built, or by the century or millennium it is known
    /// to, if that falls wholly in one era. The 2nd millennium spans five, so says
    /// nothing; the 15th century is medieval throughout.
    public static func of(_ facts: PlaceFacts) -> HistoricalEra? {
        if let year = facts.yearBuilt {
            return containing(year: year)
        }
        guard let years = facts.eraYears else { return nil }
        let first = containing(year: years.lowerBound)
        return first == containing(year: years.upperBound) ? first : nil
    }
}

/// What the user chooses to see: the culture-and-themes family (§7).
///
/// Built from the theme tags of the landmarks visited (R-DB-1), each unique landmark
/// counted once (R-CALC-3). Cities and airports carry no themes, so a log of cities
/// alone has no theme mix — the input summary says how many landmarks it rests on.
public struct ThemeStatistics: Hashable, Sendable {
    public let shares: [ThemeShare]
    public let landmarkCount: Int
    public let landmarksByEra: [HistoricalEra: Int]
    public let eraInput: StatInputSummary
    public let input: StatInputSummary
    public let personality: TravelPersonality?

    public var topThemes: [ThemeShare] {
        Array(shares.prefix(3))
    }

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        gazetteer: Gazetteer
    ) -> ThemeStatistics {
        var landmarks: [PlaceID: PlaceReference] = [:]
        for visit in log.visits where rules.countsTowardsCoverage(visit.visitType) {
            if visit.place.kind == .landmark {
                landmarks[visit.place.id] = visit.place
            }
        }

        var input = StatInputSummary()
        var eraInput = StatInputSummary()
        var weights: [String: Double] = [:]
        var eras: [HistoricalEra: Int] = [:]
        var used = 0

        for id in landmarks.keys.sorted(by: { $0.description < $1.description }) {
            let facts = gazetteer.facts(for: id)
            let themes = Set(facts?.themes ?? [])
            if themes.isEmpty {
                input.exclude(.attributeUnknown)
            } else {
                input.include()
                used += 1
                let share = 1.0 / Double(themes.count)
                for theme in themes {
                    weights[theme, default: 0] += share
                }
            }
            // A year places a landmark in its era; so does a century or millennium,
            // when the whole of it lies inside one era (R-DB-3).
            if let era = facts.flatMap(HistoricalEra.of) {
                eraInput.include()
                eras[era, default: 0] += 1
            } else {
                eraInput.exclude(.attributeUnknown)
            }
        }

        let total = weights.values.reduce(0, +)
        let shares = weights
            .map { theme, weight in
                ThemeShare(
                    theme: theme,
                    label: gazetteer.themeLabel(theme),
                    weight: weight,
                    share: total == 0 ? 0 : weight / total
                )
            }
            .sorted { ($0.weight, $1.theme) > ($1.weight, $0.theme) }

        return ThemeStatistics(
            shares: shares,
            landmarkCount: used,
            landmarksByEra: eras,
            eraInput: eraInput,
            input: input,
            personality: TravelPersonality.assess(shares: shares, landmarkCount: used)
        )
    }
}

/// A rule-based reading of the theme mix (§7.1, R-PERS-1, R-PERS-2).
///
/// Q-7 is resolved here (decision D-15): six archetypes, each a group of themes and a
/// threshold share. The archetype is the group whose share most exceeds its own
/// threshold; if none reaches its threshold the reading is the balanced Wanderer. No
/// learning, no weights hidden anywhere else — the screen shows the shares behind it.
public struct TravelPersonality: Hashable, Sendable {
    public enum Archetype: String, Sendable, CaseIterable, Identifiable {
        case historian
        case trailblazer
        case aesthete
        case pilgrim
        case futurist
        case gourmand
        case nightOwl
        case wanderer

        public var id: String {
            rawValue
        }

        public var name: String {
            switch self {
            case .historian: "Historian"
            case .trailblazer: "Trailblazer"
            case .aesthete: "Aesthete"
            case .pilgrim: "Pilgrim"
            case .futurist: "Futurist"
            case .gourmand: "Gourmand"
            case .nightOwl: "Night owl"
            case .wanderer: "Wanderer"
            }
        }

        public var summary: String {
            switch self {
            case .historian: "Drawn to ruins, castles and the stories behind them."
            case .trailblazer: "Happiest in national parks, mountains and wild places."
            case .aesthete: "Goes for galleries, palaces and beautiful buildings."
            case .pilgrim: "Seeks out temples, cathedrals and sacred sites."
            case .futurist: "Chases skylines, towers and feats of engineering."
            case .gourmand: "Travels for markets, food and drink."
            case .nightOwl: "Comes alive after dark: the streets of music, bars and late nights."
            case .wanderer: "A bit of everything — no one theme dominates."
            }
        }

        public var symbolName: String {
            switch self {
            case .historian: "building.columns"
            case .trailblazer: "mountain.2"
            case .aesthete: "paintpalette"
            case .pilgrim: "sparkles"
            case .futurist: "building.2"
            case .gourmand: "fork.knife"
            case .nightOwl: "moon.stars"
            case .wanderer: "safari"
            }
        }

        /// The themes that make up this archetype.
        public var themes: Set<String> {
            switch self {
            case .historian:
                [
                    "ancient-history", "medieval-history", "archaeology", "military-history",
                    "modern-history",
                ]
            case .trailblazer: ["nature", "national-parks", "wildlife"]
            case .aesthete: ["art-and-museums", "architecture", "palaces"]
            case .pilgrim: ["religious-sites"]
            case .futurist: ["modern-architecture", "engineering"]
            case .gourmand: ["food", "markets"]
            case .nightOwl: ["nightlife"]
            case .wanderer: []
            }
        }

        /// The share of the theme mix this group must reach to define the traveller.
        /// Lower for narrower groups: one theme in sixteen at 30% is as strong a signal
        /// as five themes at 40%.
        public var threshold: Double {
            switch self {
            case .historian, .trailblazer, .aesthete: 0.40
            case .futurist: 0.35
            case .pilgrim: 0.30
            case .gourmand, .nightOwl: 0.20
            case .wanderer: 0
            }
        }
    }

    /// One archetype's score: its share of the mix and how far past its threshold.
    public struct Score: Hashable, Sendable, Identifiable {
        public var id: Archetype {
            archetype
        }

        public let archetype: Archetype
        public let share: Double

        public var strength: Double {
            archetype.threshold == 0 ? 0 : share / archetype.threshold
        }
    }

    /// Below this many themed landmarks the mix is too thin to call.
    public static let minimumLandmarks = 5

    public let archetype: Archetype
    /// Every archetype's share, strongest first, for the "why" the screen must show
    /// (R-PERS-2).
    public let scores: [Score]
    public let landmarkCount: Int

    /// `nil` when there are too few themed landmarks to read anything into.
    public static func assess(shares: [ThemeShare], landmarkCount: Int) -> TravelPersonality? {
        guard landmarkCount >= minimumLandmarks else { return nil }
        let byTheme = Dictionary(uniqueKeysWithValues: shares.map { ($0.theme, $0.share) })
        let scores = Archetype.allCases
            .filter { $0 != .wanderer }
            .map { archetype in
                Score(
                    archetype: archetype,
                    share: archetype.themes.reduce(0) { $0 + (byTheme[$1] ?? 0) }
                )
            }
            .sorted { ($0.strength, $1.archetype.rawValue) > ($1.strength, $0.archetype.rawValue) }
        let winner = scores.first { $0.share >= $0.archetype.threshold }?.archetype ?? .wanderer
        return TravelPersonality(archetype: winner, scores: scores, landmarkCount: landmarkCount)
    }
}
