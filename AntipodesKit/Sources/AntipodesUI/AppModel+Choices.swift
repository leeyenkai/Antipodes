import AntipodesCore
import Foundation

public extension AppModel {
    // MARK: - Choices

    /// Switches the country list and repoints the denominator in one step.
    func selectCountryList(_ list: CountryList) {
        var updated = rules
        updated.countryList = list
        updated.worldCountryCount = countryListCounts[list] ?? list.fallbackCount
        rules = updated
    }

    func countryCount(for list: CountryList) -> Int {
        countryListCounts[list] ?? list.fallbackCount
    }
}
