import AntipodesCore
import Foundation

/// Persists the counting rules in `UserDefaults`.
///
/// These are preferences about how numbers are shown, not travel data, so they stay
/// local and out of CloudKit (R-CALC-1, R-CALC-4).
public enum CountingRulesStorage {
    private enum Key {
        static let includePassedThrough = "rules.includePassedThrough"
        static let includeLayovers = "rules.includeLayovers"
        static let includeCommutes = "rules.includeCommutes"
        static let unitSystem = "rules.unitSystem"
        static let worldCountryCount = "rules.worldCountryCount"
        static let countryList = "rules.countryList"
    }

    public static func load(from defaults: UserDefaults = .standard) -> CountingRules {
        let fallback = CountingRules.default
        return CountingRules(
            includePassedThrough: defaults.object(forKey: Key.includePassedThrough) as? Bool
                ?? fallback.includePassedThrough,
            includeLayovers: defaults.object(forKey: Key.includeLayovers) as? Bool
                ?? fallback.includeLayovers,
            includeCommutes: defaults.object(forKey: Key.includeCommutes) as? Bool
                ?? fallback.includeCommutes,
            unitSystem: (defaults.string(forKey: Key.unitSystem)
                .flatMap(UnitSystem.init(rawValue:))) ?? defaultUnitSystem(),
            countryList: (defaults.string(forKey: Key.countryList)
                .flatMap(CountryList.init(rawValue:))) ?? fallback.countryList,
            worldCountryCount: defaults.object(forKey: Key.worldCountryCount) as? Int
        )
    }

    public static func save(_ rules: CountingRules, to defaults: UserDefaults = .standard) {
        defaults.set(rules.includePassedThrough, forKey: Key.includePassedThrough)
        defaults.set(rules.includeLayovers, forKey: Key.includeLayovers)
        defaults.set(rules.includeCommutes, forKey: Key.includeCommutes)
        defaults.set(rules.unitSystem.rawValue, forKey: Key.unitSystem)
        defaults.set(rules.worldCountryCount, forKey: Key.worldCountryCount)
        defaults.set(rules.countryList.rawValue, forKey: Key.countryList)
    }

    /// Units follow the device's region until the user overrides them (R-CALC-4).
    static func defaultUnitSystem() -> UnitSystem {
        Locale.current.measurementSystem == .metric ? .metric : .imperial
    }
}
