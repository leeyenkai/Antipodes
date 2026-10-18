import AntipodesCore
import Foundation

/// Turns what the user typed into an FTS5 MATCH expression.
///
/// FTS5 treats `*`, `"`, `:`, `^`, `-` and `NEAR` as syntax, so raw input would be a
/// syntax error at best. Every token is quoted and the last one gets a prefix wildcard,
/// which is what makes search feel live as the user types.
enum PlaceSearchQuery {
    static func matchExpression(for input: String) -> String? {
        let tokens = input
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else { return nil }

        let quoted = tokens.enumerated().map { offset, token -> String in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            let isLast = offset == tokens.count - 1
            return isLast ? "\"\(escaped)\"*" : "\"\(escaped)\""
        }
        return quoted.joined(separator: " ")
    }
}

/// One search hit, ready to become a `PlaceReference` when the user taps it.
public struct PlaceSearchResult: Identifiable, Hashable, Sendable {
    public let id: PlaceID
    public let kind: PlaceKind
    public let name: String
    /// Context under the name, e.g. "Oslo, Norway" or "Norway · Europe".
    public let subtitle: String?
    /// ISO2, IATA or region code, shown as a chip.
    public let code: String?
    public let coordinate: Coordinate?
    public let countryCode: String?
    public let countryName: String?
    public let continent: Continent?
    public let regionCode: String?
    public let regionName: String?
    public let cityID: Int64?
    public let cityName: String?
    /// Population or curated fame, used for ranking (R-LOG-1).
    public let prominence: Int

    /// The reference stored in the user's log. Carries the whole hierarchy chain so
    /// stats never need the database again (R-MODEL-6).
    public var placeReference: PlaceReference {
        PlaceReference(
            id: id,
            kind: kind,
            name: name,
            coordinate: coordinate,
            countryCode: countryCode,
            countryName: countryName,
            continent: continent,
            regionCode: regionCode,
            regionName: regionName,
            cityID: cityID,
            cityName: cityName
        )
    }
}

/// Version and provenance of the bundled database, shown in Settings and used to
/// decide whether an update is needed (R-DB-5).
public struct PlaceDatabaseInfo: Hashable, Sendable {
    public let schemaVersion: Int
    public let dataVersion: String
    public let builtAt: String
    public let rowCounts: [PlaceKind: Int]

    public var totalRows: Int {
        rowCounts.values.reduce(0, +)
    }
}
