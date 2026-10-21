import Foundation

/// Why a record did not make it into a statistic, or onto the globe.
public enum ExclusionReason: String, Sendable, Codable, CaseIterable, Comparable {
    /// Visit type does not count towards coverage under the current rules (R-CALC-1).
    case visitTypeNotCounted
    /// The stat needs a date and the record has none (R-DATE-2).
    case unknownDate
    /// The record has no country, so it cannot be placed.
    case missingCountry
    /// No coordinate, so no distance and no globe position.
    case missingCoordinate
    /// A commute, and commutes are switched out of stats (Q-15).
    case commuteExcluded
    /// No distance could be worked out for the leg at all.
    case distanceUnavailable
    /// The stat needs a day, and the record only says a month or a year (R-DATE-2).
    case datePrecisionTooLow
    /// The place database has no value for the attribute this stat measures (R-DB-2).
    case attributeUnknown
    /// The leg has no times, or not the time zones needed to read them.
    case timesUnavailable
    /// No published carbon factor covers this mode (R-CO2-3).
    case noEmissionFactor
    /// Not in a trip, for a stat that is about trips.
    case notInATrip
    /// At the user's home, for a stat about being away from it.
    case atHome
    /// A transit ride logged between two places rather than on a line of a transit
    /// pack, so its segments are unknown (R-TRAN-2).
    case noTransitLine
    /// The line's segments do not join the two stops: a gap in the network data.
    case transitRouteUnknown

    public var explanation: String {
        switch self {
        case .visitTypeNotCounted: "not counted by your coverage rules"
        case .unknownDate: "no date recorded"
        case .missingCountry: "no country resolved"
        case .missingCoordinate: "no location recorded"
        case .commuteExcluded: "commute, excluded from stats"
        case .distanceUnavailable: "no distance available"
        case .datePrecisionTooLow: "no exact day recorded"
        case .attributeUnknown: "not known for that place"
        case .timesUnavailable: "no usable times"
        case .noEmissionFactor: "no carbon factor for that mode"
        case .notInATrip: "not in a trip"
        case .atHome: "at home"
        case .noTransitLine: "not logged on a transit line"
        case .transitRouteUnknown: "stops not joined on the line"
        }
    }

    public static func < (lhs: ExclusionReason, rhs: ExclusionReason) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How much of its input a statistic — or the globe — could actually use.
///
/// Every stat in the app carries one of these. A number that quietly dropped half the
/// user's records is worse than no number, so this is not optional bookkeeping
/// (R-CALC-5, R-DB-2). It lives in Core rather than in `AntipodesStats` because the
/// globe reports the same way about the pins and arcs it could not draw, and the two
/// should not word it differently.
public struct StatInputSummary: Hashable, Sendable, Codable {
    public private(set) var considered: Int
    public private(set) var used: Int
    public private(set) var exclusions: [ExclusionReason: Int]

    public init() {
        considered = 0
        used = 0
        exclusions = [:]
    }

    public mutating func include() {
        considered += 1
        used += 1
    }

    public mutating func exclude(_ reason: ExclusionReason) {
        considered += 1
        exclusions[reason, default: 0] += 1
    }

    public var excludedCount: Int {
        exclusions.values.reduce(0, +)
    }

    public var isComplete: Bool {
        excludedCount == 0
    }

    /// Fraction of input used, in 0...1. An empty input is complete, not zero.
    public var completeness: Double {
        considered == 0 ? 1 : Double(used) / Double(considered)
    }

    /// A sentence for under the number, or `nil` when nothing was dropped.
    ///
    /// e.g. `"Based on 42 of 50 records; 6 no date recorded, 2 no country resolved."`
    public var caveat: String? {
        caveat(counting: "records")
    }

    /// The same sentence, naming what was counted: "Based on 42 of 50 landmarks".
    public func caveat(counting noun: String) -> String? {
        guard !isComplete else { return nil }
        let reasons = exclusions
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.value) \($0.key.explanation)" }
            .joined(separator: ", ")
        return "Based on \(used) of \(considered) \(noun); \(reasons)."
    }

    /// Two summaries added together, for a stat built from several passes.
    public static func + (lhs: StatInputSummary, rhs: StatInputSummary) -> StatInputSummary {
        var result = lhs
        result.considered += rhs.considered
        result.used += rhs.used
        for (reason, count) in rhs.exclusions {
            result.exclusions[reason, default: 0] += count
        }
        return result
    }
}
