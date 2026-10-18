import AntipodesCore
import Foundation

/// Why a record did not make it into a statistic.
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

    public var explanation: String {
        switch self {
        case .visitTypeNotCounted: "not counted by your coverage rules"
        case .unknownDate: "no date recorded"
        case .missingCountry: "no country resolved"
        case .missingCoordinate: "no location recorded"
        case .commuteExcluded: "commute, excluded from stats"
        case .distanceUnavailable: "no distance available"
        }
    }

    public static func < (lhs: ExclusionReason, rhs: ExclusionReason) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// How much of its input a statistic could actually use.
///
/// Every stat in the app carries one of these. A number that quietly dropped half the
/// user's records is worse than no number, so this is not optional bookkeeping
/// (R-CALC-5, R-DB-2).
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
        guard !isComplete else { return nil }
        let reasons = exclusions
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { "\($0.value) \($0.key.explanation)" }
            .joined(separator: ", ")
        return "Based on \(used) of \(considered) records; \(reasons)."
    }
}
