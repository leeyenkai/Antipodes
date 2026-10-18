import Foundation

/// How substantial a visit was.
///
/// This drives coverage: "passed through" a country on a train is not the same as
/// having been there, so by default it does not count (§3.1, R-CALC-1).
public enum VisitType: String, Sendable, Codable, CaseIterable, Identifiable {
    case stayed
    case dayTrip
    case passedThrough
    case layover

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .stayed: "Stayed"
        case .dayTrip: "Day trip"
        case .passedThrough: "Passed through"
        case .layover: "Layover"
        }
    }

    public var explanation: String {
        switch self {
        case .stayed: "At least one night there"
        case .dayTrip: "Visited without staying overnight"
        case .passedThrough: "Crossed it by road, rail or sea without stopping to visit"
        case .layover: "Changed planes or trains without leaving the station or airport"
        }
    }

    public var symbolName: String {
        switch self {
        case .stayed: "moon.stars"
        case .dayTrip: "sun.max"
        case .passedThrough: "arrow.right.to.line"
        case .layover: "airplane.arrival"
        }
    }

    /// Whether this type counts towards coverage when the user has not changed the
    /// setting (R-CALC-1). `CountingRules` is what stats actually consult.
    public var countsTowardsCoverageByDefault: Bool {
        switch self {
        case .stayed, .dayTrip: true
        case .passedThrough, .layover: false
        }
    }
}

/// Why a leg was travelled. Commutes can be kept out of stats so a daily tram ride
/// does not swamp the numbers (Q-15).
public enum TripPurpose: String, Sendable, Codable, CaseIterable, Identifiable {
    case leisure
    case work
    case commute

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .leisure: "Leisure"
        case .work: "Work"
        case .commute: "Commute"
        }
    }
}
