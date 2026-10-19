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
    /// IANA zone, where the database has one (§5.2).
    public let timeZoneIdentifier: String?

    public init(
        id: PlaceID,
        kind: PlaceKind,
        name: String,
        subtitle: String? = nil,
        code: String? = nil,
        coordinate: Coordinate? = nil,
        countryCode: String? = nil,
        countryName: String? = nil,
        continent: Continent? = nil,
        regionCode: String? = nil,
        regionName: String? = nil,
        cityID: Int64? = nil,
        cityName: String? = nil,
        prominence: Int = 0,
        timeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.subtitle = subtitle
        self.code = code
        self.coordinate = coordinate
        self.countryCode = countryCode
        self.countryName = countryName
        self.continent = continent
        self.regionCode = regionCode
        self.regionName = regionName
        self.cityID = cityID
        self.cityName = cityName
        self.prominence = prominence
        self.timeZoneIdentifier = timeZoneIdentifier
    }

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
            cityName: cityName,
            timeZoneIdentifier: timeZoneIdentifier,
            code: code
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
    /// Which GeoNames populated-place extract the database was built from (Q-5).
    public let citiesDataset: String
    /// Every upstream source, for the attribution list in Settings (R-DB-7).
    public let sources: [PlaceDataSource]

    public var totalRows: Int {
        rowCounts.values.reduce(0, +)
    }

    /// The credit lines a licence actually requires, in source order.
    ///
    /// Only GeoNames obliges one today; Natural Earth, OurAirports and Wikidata are
    /// public domain or CC0. Showing the required ones separately keeps the obligation
    /// visible rather than buried in a list of everything.
    public var requiredAttributions: [String] {
        sources.compactMap(\.attribution)
    }
}

/// One upstream source and what it obliges, read straight out of the database.
///
/// This travels inside the artefact rather than being compiled into the app, so a
/// source cannot be added to the pipeline without its credit appearing in Settings
/// (R-DB-7). See `Tools/placedb/SOURCES.md` for the licence review behind each row.
public struct PlaceDataSource: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let url: String
    public let licence: String
    public let licenceURL: String?
    /// The credit the licence requires, verbatim, or `nil` where none is required.
    public let attribution: String?
    /// What the pipeline used this source for, in one phrase.
    public let usedFor: String
    /// Digest of the files this build read, and the date they were retrieved. Both are
    /// `nil` for the curation, which is part of the repository rather than a download.
    public let sha256: String?
    public let retrieved: String?

    public init(
        id: String,
        name: String,
        url: String,
        licence: String,
        licenceURL: String?,
        attribution: String?,
        usedFor: String,
        sha256: String?,
        retrieved: String?
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.licence = licence
        self.licenceURL = licenceURL
        self.attribution = attribution
        self.usedFor = usedFor
        self.sha256 = sha256
        self.retrieved = retrieved
    }
}
