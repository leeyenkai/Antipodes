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

    /// How many countries "% of the world" is measured against.
    ///
    /// Which places count as a country is unresolved (Q-4), so the denominator is
    /// configuration rather than a constant. The default is the 193 UN member states.
    public var worldCountryCount: Int

    public static let `default` = CountingRules()

    public init(
        includePassedThrough: Bool = false,
        includeLayovers: Bool = false,
        includeCommutes: Bool = false,
        unitSystem: UnitSystem = .metric,
        worldCountryCount: Int = 193
    ) {
        self.includePassedThrough = includePassedThrough
        self.includeLayovers = includeLayovers
        self.includeCommutes = includeCommutes
        self.unitSystem = unitSystem
        self.worldCountryCount = max(1, worldCountryCount)
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
