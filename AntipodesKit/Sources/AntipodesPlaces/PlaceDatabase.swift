import AntipodesCore
import Foundation

/// The read-only place database that ships inside the app (R-DB-4).
///
/// An actor because the SQLite connection is not thread-safe and search will eventually
/// run off the main thread. Opening read-only means a bug here cannot corrupt the file,
/// and nothing in this type touches the network — searches never leave the device
/// (R-PRIV-3).
public actor PlaceDatabase {
    /// Schema version this code expects. The pipeline writes the same number into
    /// `meta`, and a mismatch is an error rather than a wrong query.
    public static let expectedSchemaVersion = 1

    private let connection: SQLiteConnection
    public let path: String

    public init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw PlaceDatabaseError.fileMissing(path: path)
        }
        connection = try SQLiteConnection(readOnlyPath: path)
        self.path = path

        let version = try Self.readSchemaVersion(from: connection)
        guard version == Self.expectedSchemaVersion else {
            throw PlaceDatabaseError.schemaMismatch(
                found: version,
                expected: Self.expectedSchemaVersion
            )
        }
    }

    private static func readSchemaVersion(from connection: SQLiteConnection) throws -> Int {
        let value = try connection.queryOne(
            "SELECT value FROM meta WHERE key = ?",
            parameters: [.text("schema_version")]
        ) { try $0.requiredString(0) }
        guard let value, let version = Int(value) else {
            throw PlaceDatabaseError.schemaMismatch(found: 0, expected: expectedSchemaVersion)
        }
        return version
    }

    // MARK: - Search

    /// Searches every place type at once, which is the single search field in the add
    /// sheet (R-LOG-1).
    ///
    /// Ranking puts an exact name or code match first, then a prefix match, then
    /// prominence — population for cities, curated fame for landmarks. This is why
    /// typing "par" offers Paris before Parma.
    public func search(
        _ text: String,
        kinds: Set<PlaceKind>? = nil,
        limit: Int = 25
    ) throws -> [PlaceSearchResult] {
        guard let match = PlaceSearchQuery.matchExpression(for: text) else { return [] }

        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // SQLite binds `?` by position in the SQL text, so this array is assembled in
        // the order the placeholders appear below — MATCH, then the kind filter, then
        // the three ranking comparisons, then LIMIT. Appending out of order silently
        // binds a kind where a search term belongs and the query matches nothing.
        var parameters: [SQLiteValue] = [.text(match)]

        var kindFilter = ""
        if let kinds, !kinds.isEmpty {
            let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ", ")
            kindFilter = "AND p.kind IN (\(placeholders))"
            parameters.append(contentsOf: kinds.sorted { $0.rawValue < $1.rawValue }
                .map { SQLiteValue.text($0.rawValue) })
        }

        parameters.append(contentsOf: [.text(needle), .text(needle), .text(needle)])
        parameters.append(.integer(Int64(max(1, limit))))

        let sql = """
        SELECT p.kind, p.ref_id, p.name, p.subtitle, p.code,
               p.country_iso2, p.country_name, p.continent,
               p.region_code, p.region_name, p.city_id, p.city_name,
               p.latitude, p.longitude, p.prominence
        FROM place_fts
        JOIN place_index AS p ON p.rowid = place_fts.rowid
        WHERE place_fts MATCH ?
        \(kindFilter)
        ORDER BY
            CASE
                WHEN lower(p.name) = ? THEN 0
                WHEN lower(COALESCE(p.code, '')) = ? THEN 0
                WHEN lower(p.name) LIKE ? || '%' THEN 1
                ELSE 2
            END ASC,
            p.prominence DESC,
            p.name ASC
        LIMIT ?
        """

        return try connection.query(sql, parameters: parameters, row: Self.decodeResult)
    }

    // MARK: - Lookups

    public func place(kind: PlaceKind, id: Int64) throws -> PlaceSearchResult? {
        try connection.queryOne(
            """
            SELECT p.kind, p.ref_id, p.name, p.subtitle, p.code,
                   p.country_iso2, p.country_name, p.continent,
                   p.region_code, p.region_name, p.city_id, p.city_name,
                   p.latitude, p.longitude, p.prominence
            FROM place_index AS p
            WHERE p.kind = ? AND p.ref_id = ?
            """,
            parameters: [.text(kind.rawValue), .integer(id)],
            row: Self.decodeResult
        )
    }

    /// Finds an airport by IATA or ICAO code. Used by the flight importer and by
    /// typing a bare code into search.
    public func airport(code: String) throws -> PlaceSearchResult? {
        let normalised = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard (3 ... 4).contains(normalised.count) else { return nil }
        return try connection.queryOne(
            """
            SELECT p.kind, p.ref_id, p.name, p.subtitle, p.code,
                   p.country_iso2, p.country_name, p.continent,
                   p.region_code, p.region_name, p.city_id, p.city_name,
                   p.latitude, p.longitude, p.prominence
            FROM place_index AS p
            WHERE p.kind = 'airport' AND upper(COALESCE(p.code, '')) = ?
            """,
            parameters: [.text(normalised)],
            row: Self.decodeResult
        )
    }

    /// Resolves a dropped pin to a country by bounding box, then by nearest city.
    ///
    /// A stand-in for real point-in-polygon geocoding against bundled borders
    /// (R-LOG-5). It is good enough to prove the flow and wrong near borders; the
    /// bundled border polygons replace it, and the signature does not change.
    public func approximateCountry(for coordinate: Coordinate) throws -> PlaceSearchResult? {
        try connection.queryOne(
            """
            SELECT p.kind, p.ref_id, p.name, p.subtitle, p.code,
                   p.country_iso2, p.country_name, p.continent,
                   p.region_code, p.region_name, p.city_id, p.city_name,
                   p.latitude, p.longitude, p.prominence
            FROM place_index AS p
            WHERE p.kind = 'country' AND p.latitude IS NOT NULL
            ORDER BY (
                (p.latitude - ?) * (p.latitude - ?)
                + (p.longitude - ?) * (p.longitude - ?)
            ) ASC
            LIMIT 1
            """,
            parameters: [
                .double(coordinate.latitude), .double(coordinate.latitude),
                .double(coordinate.longitude), .double(coordinate.longitude),
            ],
            row: Self.decodeResult
        )
    }

    public func info() throws -> PlaceDatabaseInfo {
        func metaValue(_ key: String) throws -> String {
            try connection.queryOne(
                "SELECT value FROM meta WHERE key = ?",
                parameters: [.text(key)]
            ) { try $0.requiredString(0) } ?? "unknown"
        }

        let counts = try connection.query(
            "SELECT kind, COUNT(*) FROM place_index GROUP BY kind"
        ) { row in
            try (row.requiredString(0), row.int(1) ?? 0)
        }

        var rowCounts: [PlaceKind: Int] = [:]
        for (rawKind, count) in counts {
            if let kind = PlaceKind(rawValue: rawKind) {
                rowCounts[kind] = count
            }
        }

        return try PlaceDatabaseInfo(
            schemaVersion: Self.expectedSchemaVersion,
            dataVersion: metaValue("data_version"),
            builtAt: metaValue("built_at"),
            rowCounts: rowCounts
        )
    }

    // MARK: - Decoding

    private static func decodeResult(_ row: SQLiteRow) throws -> PlaceSearchResult {
        let rawKind = try row.requiredString(0)
        guard let kind = PlaceKind(rawValue: rawKind) else {
            throw PlaceDatabaseError.unknownPlaceKind(rawKind)
        }
        let refID = try row.requiredInt64(1)

        let coordinate: Coordinate? =
            if let latitude = row.double(12), let longitude = row.double(13) {
                Coordinate(latitude: latitude, longitude: longitude)
            } else {
                nil
            }

        return try PlaceSearchResult(
            id: .database(kind, refID),
            kind: kind,
            name: row.requiredString(2),
            subtitle: row.string(3),
            code: row.string(4),
            coordinate: coordinate,
            countryCode: row.string(5),
            countryName: row.string(6),
            continent: row.string(7).flatMap(Continent.init(rawValue:)),
            regionCode: row.string(8),
            regionName: row.string(9),
            cityID: row.int64(10),
            cityName: row.string(11),
            prominence: row.int(14) ?? 0
        )
    }
}

public enum PlaceDatabaseError: Error, CustomStringConvertible {
    case fileMissing(path: String)
    case schemaMismatch(found: Int, expected: Int)
    case unknownPlaceKind(String)

    public var description: String {
        switch self {
        case let .fileMissing(path):
            "The place database is not at \(path). Run scripts/build-placedb.sh."
        case let .schemaMismatch(found, expected):
            "Place database schema \(found), but this build expects \(expected)."
        case let .unknownPlaceKind(kind):
            "Place database contains an unknown place kind: \(kind)."
        }
    }
}
