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
    public static let expectedSchemaVersion = 6

    /// How prominent a row must be for an exact name match to promote it above more
    /// prominent prefix matches.
    ///
    /// Searching "par" matches *Par*, a Cornish village of nine thousand, exactly.
    /// Promoting it above Paris because the user happened to type a complete name is
    /// not what anyone means, so the promotion is reserved for places someone
    /// plausibly searched for.
    ///
    /// The floor is in the same units as `place_index.prominence`, so for a city it is
    /// a population. 25,000 is low enough that a real town keeps its exact match —
    /// Tromsø has 41,915 people and should outrank Tromsø Airport when its name is
    /// typed in full — and high enough to leave hamlets out. Every country, region,
    /// large airport and well-known landmark is above it by construction.
    public static let exactMatchProminenceFloor: Int64 = 25000

    /// Internal rather than private so the test suite can assert table-wide invariants
    /// — that every landmark carries a theme, that every `source` names a registered
    /// data source — which no public query exposes and which the app has no reason to
    /// ask. Nothing outside the module can reach it.
    let connection: SQLiteConnection
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
    /// Ranking has three keys, and each one is there because of a case that got it
    /// wrong on real data:
    ///
    /// 1. **Match class.** An exact name or code match outranks a prefix match, which
    ///    outranks a mere token hit — but only if the row clears
    ///    ``exactMatchProminenceFloor``. Without that floor, typing "par" offered
    ///    *Par*, a Cornish village of nine thousand, ahead of Paris, purely because it
    ///    had been typed in full.
    /// 2. **Kind**, among exact matches only. "Singapore" offers the country before the
    ///    city of the same name, and "Oslo" the city before the region.
    /// 3. **Prominence**, on one scale across kinds, so a famous city beats an obscure
    ///    country. This is what makes "par" offer Paris before Parma — and before
    ///    Paraguay.
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

        // Bound in the order the `?` placeholders appear in the SQL below: the three
        // exact comparisons and the floor for the match class, the two LIKEs for the
        // prefix class, then the same four again for the kind tiebreak.
        //
        // The needle is compared against both `name` and `name_folded` without being
        // folded here. That is deliberate: the folding rules — ø→o, æ→ae, ß→ss and the
        // rest — live in the pipeline, and reimplementing them in Swift would be two
        // copies to keep in step. Someone typing "zurich" matches the folded column and
        // someone typing "Zürich" matches the raw one.
        parameters.append(contentsOf: [
            .text(needle), .text(needle), .text(needle),
            .integer(Self.exactMatchProminenceFloor),
            .text(needle), .text(needle),
            .text(needle), .text(needle), .text(needle),
            .integer(Self.exactMatchProminenceFloor),
        ])
        parameters.append(.integer(Int64(max(1, limit))))

        let sql = """
        SELECT p.kind, p.ref_id, p.name, p.subtitle, p.code,
               p.country_iso2, p.country_name, p.continent,
               p.region_code, p.region_name, p.city_id, p.city_name,
               p.latitude, p.longitude, p.prominence, p.timezone
        FROM place_fts
        JOIN place_index AS p ON p.rowid = place_fts.rowid
        WHERE place_fts MATCH ?
        \(kindFilter)
        ORDER BY
            CASE
                WHEN (lower(p.name) = ? OR p.name_folded = ?
                      OR lower(COALESCE(p.code, '')) = ?)
                     AND p.prominence >= ? THEN 2
                WHEN lower(p.name) LIKE ? || '%' OR p.name_folded LIKE ? || '%' THEN 1
                ELSE 0
            END DESC,
            CASE
                WHEN (lower(p.name) = ? OR p.name_folded = ?
                      OR lower(COALESCE(p.code, '')) = ?)
                     AND p.prominence >= ? THEN p.kind_rank
                ELSE 0
            END DESC,
            p.prominence DESC,
            p.name ASC
        LIMIT ?
        """

        return try connection.query(sql, parameters: parameters, row: Self.decodeSearchResult(_:))
    }

    // MARK: - Lookups

    public func place(kind: PlaceKind, id: Int64) throws -> PlaceSearchResult? {
        try connection.queryOne(
            """
            SELECT \(Self.resultColumns)
            FROM place_index AS p
            WHERE p.kind = ? AND p.ref_id = ?
            """,
            parameters: [.text(kind.rawValue), .integer(id)],
            row: Self.decodeSearchResult(_:)
        )
    }

    /// Finds an airport by IATA or ICAO code. Used by the flight importer and by
    /// typing a bare code into search.
    ///
    /// The search index carries only the IATA code, so a four-letter ICAO code is looked
    /// up in the airport table itself. An IATA match wins if a code is somehow both.
    public func airport(code: String) throws -> PlaceSearchResult? {
        let normalised = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard (3 ... 4).contains(normalised.count) else { return nil }
        return try connection.queryOne(
            """
            SELECT \(Self.resultColumns)
            FROM place_index AS p
            WHERE p.kind = 'airport' AND (
                upper(COALESCE(p.code, '')) = ?
                OR p.ref_id IN (SELECT id FROM airport WHERE upper(COALESCE(icao, '')) = ?)
            )
            ORDER BY upper(COALESCE(p.code, '')) = ? DESC
            LIMIT 1
            """,
            parameters: [.text(normalised), .text(normalised), .text(normalised)],
            row: Self.decodeSearchResult(_:)
        )
    }

    /// Resolves a dropped pin to a country by finding the nearest bundled city and
    /// returning the country it is in.
    ///
    /// A stand-in for real point-in-polygon geocoding (R-LOG-5), and still wrong in the
    /// open ocean and sometimes within a few kilometres of a border. Nearest *city*
    /// rather than nearest country centroid because the database holds seventy thousand
    /// cities and no country centroid at all: a centroid would have to be invented,
    /// while a city coordinate is a fact GeoNames publishes. It is also much the better
    /// estimate — a pin in Trondheim is hundreds of kilometres from Norway's middle but
    /// metres from a city GeoNames knows.
    ///
    /// The real answer is point-in-polygon against the Natural Earth borders that
    /// `Tools/placedb/build_borders.py` compiles for the globe (decision D-5). This
    /// signature does not change when that lands.
    ///
    /// Squared degrees, not great-circle distance: it is monotonic in the same order for
    /// nearby candidates, and SQLite can compute it without a function call.
    public func approximateCountry(for coordinate: Coordinate) throws -> PlaceSearchResult? {
        let nearestCountryCode = try connection.queryOne(
            """
            SELECT country_iso2
            FROM city
            ORDER BY (
                (latitude - ?) * (latitude - ?)
                + (longitude - ?) * (longitude - ?)
            ) ASC
            LIMIT 1
            """,
            parameters: [
                .double(coordinate.latitude), .double(coordinate.latitude),
                .double(coordinate.longitude), .double(coordinate.longitude),
            ]
        ) { try $0.requiredString(0) }

        guard let nearestCountryCode else { return nil }

        return try connection.queryOne(
            """
            SELECT \(Self.resultColumns)
            FROM place_index AS p
            WHERE p.kind = 'country' AND p.country_iso2 = ?
            """,
            parameters: [.text(nearestCountryCode)],
            row: Self.decodeSearchResult(_:)
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
            rowCounts: rowCounts,
            citiesDataset: metaValue("cities_dataset"),
            sources: dataSources()
        )
    }

    /// Every upstream source and what it obliges (R-DB-7).
    public func dataSources() throws -> [PlaceDataSource] {
        try connection.query(
            """
            SELECT id, name, url, licence, licence_url, attribution, used_for,
                   sha256, retrieved
            FROM data_source
            ORDER BY name
            """
        ) { row in
            try PlaceDataSource(
                id: row.requiredString(0),
                name: row.requiredString(1),
                url: row.requiredString(2),
                licence: row.requiredString(3),
                licenceURL: row.string(4),
                attribution: row.string(5),
                usedFor: row.requiredString(6),
                sha256: row.string(7),
                retrieved: row.string(8)
            )
        }
    }

    /// How many countries each of the lists the user can choose between contains.
    ///
    /// Read from the database rather than compiled in, because which places count as a
    /// country is the user's choice and the denominators follow the data (Q-4,
    /// decision D-6). A list missing from `meta` falls back to the compiled-in count,
    /// so an older database still works.
    public func countryListCounts() throws -> [CountryList: Int] {
        var counts: [CountryList: Int] = [:]
        for list in CountryList.allCases {
            let value = try connection.queryOne(
                "SELECT value FROM meta WHERE key = ?",
                parameters: [.text(list.metaKey)]
            ) { try $0.requiredString(0) }
            counts[list] = value.flatMap(Int.init) ?? list.fallbackCount
        }
        return counts
    }

    // MARK: - Decoding

    /// The `place_index` columns `decodeResult` reads, in its order.
    static let resultColumns = """
    p.kind, p.ref_id, p.name, p.subtitle, p.code,
    p.country_iso2, p.country_name, p.continent,
    p.region_code, p.region_name, p.city_id, p.city_name,
    p.latitude, p.longitude, p.prominence, p.timezone
    """

    static func decodeSearchResult(_ row: SQLiteRow) throws -> PlaceSearchResult {
        try decodeSearchResult(row, offset: 0)
    }

    /// Decodes the `resultColumns` starting at column `offset`, so a query can put its
    /// own columns first.
    static func decodeSearchResult(_ row: SQLiteRow, offset: Int32) throws -> PlaceSearchResult {
        let rawKind = try row.requiredString(offset + 0)
        guard let kind = PlaceKind(rawValue: rawKind) else {
            throw PlaceDatabaseError.unknownPlaceKind(rawKind)
        }
        let refID = try row.requiredInt64(offset + 1)

        let coordinate: Coordinate? =
            if let latitude = row.double(offset + 12), let longitude = row.double(offset + 13) {
                Coordinate(latitude: latitude, longitude: longitude)
            } else {
                nil
            }

        return try PlaceSearchResult(
            id: .database(kind, refID),
            kind: kind,
            name: row.requiredString(offset + 2),
            subtitle: row.string(offset + 3),
            code: row.string(offset + 4),
            coordinate: coordinate,
            countryCode: row.string(offset + 5),
            countryName: row.string(offset + 6),
            continent: row.string(offset + 7).flatMap(Continent.init(rawValue:)),
            regionCode: row.string(offset + 8),
            regionName: row.string(offset + 9),
            cityID: row.int64(offset + 10),
            cityName: row.string(offset + 11),
            prominence: row.int(offset + 14) ?? 0,
            timeZoneIdentifier: row.string(offset + 15)
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
