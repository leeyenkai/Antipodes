import AntipodesCore
import Foundation

// The parts of the place database that are not search: facts for the statistics,
// curated collections, achievement definitions, the route catalogue and carbon factors.
// Everything here is read-only and identical for every user (R-PRIV-3).

public extension PlaceDatabase {
    // MARK: - Lookups by identity

    /// Every place in `ids` that the database knows, keyed by identity. Custom pins and
    /// ids from a newer database are simply absent from the answer.
    func places(for ids: some Sequence<PlaceID>) throws -> [PlaceID: PlaceSearchResult] {
        var byKind: [PlaceKind: [Int64]] = [:]
        for id in ids {
            if case let .database(kind, row) = id {
                byKind[kind, default: []].append(row)
            }
        }
        var found: [PlaceID: PlaceSearchResult] = [:]
        for (kind, rows) in byKind.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for chunk in rows.chunked(into: 400) {
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let results = try connection.query(
                    """
                    SELECT \(Self.resultColumns)
                    FROM place_index AS p
                    WHERE p.kind = ? AND p.ref_id IN (\(placeholders))
                    """,
                    parameters: [.text(kind.rawValue)] + chunk.map { .integer($0) },
                    row: Self.decodeSearchResult(_:)
                )
                for result in results {
                    found[result.id] = result
                }
            }
        }
        return found
    }

    /// A country by its ISO 3166-1 alpha-2 code.
    func country(code: String) throws -> PlaceSearchResult? {
        try connection.queryOne(
            """
            SELECT \(Self.resultColumns)
            FROM place_index AS p
            WHERE p.kind = 'country' AND p.country_iso2 = ?
            """,
            parameters: [.text(code.uppercased())],
            row: Self.decodeSearchResult(_:)
        )
    }

    /// The nearest bundled city within `radiusKm`, or `nil` when there is none.
    ///
    /// Used to name where a dropped pin or a photo is (R-LOG-5, R-LOG-7). Narrowed by a
    /// latitude band on an index first, then measured properly with the one great-circle
    /// implementation (AGENTS.md §7) — so the answer is the truly nearest city, and the
    /// query stays fast enough to run for every photo in an import.
    func nearestCity(to coordinate: Coordinate, withinKm radiusKm: Double = 40) throws
        -> PlaceSearchResult? {
        let latitudeSpan = radiusKm / 111.0
        let cosine = max(0.01, cos(coordinate.latitudeRadians))
        let longitudeSpan = radiusKm / (111.0 * cosine)
        var sql = """
        SELECT id, latitude, longitude FROM city
        WHERE latitude BETWEEN ? AND ?
        """
        var parameters: [SQLiteValue] = [
            .double(coordinate.latitude - latitudeSpan),
            .double(coordinate.latitude + latitudeSpan),
        ]
        // Near the antimeridian the longitude band would wrap; the latitude band alone
        // is still a small candidate set there, so it is left unbounded.
        let west = coordinate.longitude - longitudeSpan
        let east = coordinate.longitude + longitudeSpan
        if west > -180, east < 180, longitudeSpan < 90 {
            sql += " AND longitude BETWEEN ? AND ?"
            parameters += [.double(west), .double(east)]
        }
        let candidates = try connection.query(sql, parameters: parameters) { row in
            try (row.requiredInt64(0), row.double(1) ?? 0, row.double(2) ?? 0)
        }
        let nearest = candidates
            .map { candidate in
                (
                    id: candidate.0,
                    distance: GreatCircle.distanceKm(
                        from: coordinate,
                        to: Coordinate(latitude: candidate.1, longitude: candidate.2)
                    )
                )
            }
            .filter { $0.distance <= radiusKm }
            .min { ($0.distance, $0.id) < ($1.distance, $1.id) }
        guard let nearest else { return nil }
        return try place(kind: .city, id: nearest.id)
    }

    // MARK: - Facts for statistics

    // One query per place kind, read side by side.
    // swiftlint:disable function_body_length
    /// Attributes for every bundled place in `ids`, for the place-attribute stats.
    func facts(for ids: some Sequence<PlaceID>) throws -> [PlaceID: PlaceFacts] {
        var byKind: [PlaceKind: [Int64]] = [:]
        for id in Set(ids) {
            if case let .database(kind, row) = id {
                byKind[kind, default: []].append(row)
            }
        }
        var facts: [PlaceID: PlaceFacts] = [:]

        /// Runs `sql` over this kind's ids in chunks; `IDS` in it stands for the list.
        func each(
            _ kind: PlaceKind,
            sql: String,
            decode: (SQLiteRow) throws -> (Int64, PlaceFacts)
        ) throws {
            for chunk in (byKind[kind] ?? []).sorted().chunked(into: 400) {
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let rows = try connection.query(
                    sql.replacingOccurrences(of: "IDS", with: placeholders),
                    parameters: chunk.map { .integer($0) },
                    row: decode
                )
                for (row, fact) in rows {
                    facts[.database(kind, row)] = fact
                }
            }
        }

        try each(.city, sql: """
        SELECT id, population, elevation_m, timezone, is_capital FROM city WHERE id IN (IDS)
        """) { row in
            try (
                row.requiredInt64(0),
                PlaceFacts(
                    population: row.int(1),
                    elevationM: row.double(2),
                    timeZoneIdentifier: row.string(3),
                    isCapital: row.bool(4)
                )
            )
        }
        try each(.landmark, sql: """
        SELECT l.id, l.year_built, l.height_m, l.unesco, l.themes, l.kind, p.timezone
        FROM landmark AS l
        LEFT JOIN place_index AS p ON p.kind = 'landmark' AND p.ref_id = l.id
        WHERE l.id IN (IDS)
        """) { row in
            try (
                row.requiredInt64(0),
                PlaceFacts(
                    timeZoneIdentifier: row.string(6),
                    yearBuilt: row.int(1),
                    heightM: row.double(2),
                    isUNESCO: row.bool(3),
                    themes: (row.string(4) ?? "")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty },
                    landmarkKind: row.string(5)
                )
            )
        }
        try each(
            .airport,
            sql: "SELECT id, elevation_m, timezone FROM airport WHERE id IN (IDS)"
        ) { row in
            try (
                row.requiredInt64(0),
                PlaceFacts(elevationM: row.double(1), timeZoneIdentifier: row.string(2))
            )
        }
        try each(.country, sql: """
        SELECT c.id, c.population, p.timezone
        FROM country AS c
        LEFT JOIN place_index AS p ON p.kind = 'country' AND p.ref_id = c.id
        WHERE c.id IN (IDS)
        """) { row in
            try (
                row.requiredInt64(0),
                PlaceFacts(population: row.int(1), timeZoneIdentifier: row.string(2))
            )
        }
        try each(.region, sql: """
        SELECT ref_id, timezone FROM place_index WHERE kind = 'region' AND ref_id IN (IDS)
        """) { row in
            try (row.requiredInt64(0), PlaceFacts(timeZoneIdentifier: row.string(1)))
        }
        try addClimate(to: &facts, kinds: byKind)
        return facts
    }

    /// Each place's monthly temperature normals and climate zone, merged into its facts
    /// (R-CALC-2). Kept apart from the per-kind queries: one table serves three kinds.
    private func addClimate(
        to facts: inout [PlaceID: PlaceFacts],
        kinds byKind: [PlaceKind: [Int64]]
    ) throws {
        for kind in [PlaceKind.city, .landmark, .airport] {
            for chunk in (byKind[kind] ?? []).sorted().chunked(into: 400) {
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let rows = try connection.query(
                    """
                    SELECT ref_id, tmean_tenths, koppen FROM climate
                    WHERE place_kind = ? AND ref_id IN (\(placeholders))
                    """,
                    parameters: [.text(kind.rawValue)] + chunk.map { .integer($0) }
                ) { row in
                    try (row.requiredInt64(0), row.requiredString(1), row.string(2))
                }
                for (ref, tenths, koppen) in rows {
                    let months = tenths.split(separator: ",").compactMap { Double($0) }
                        .map { $0 / 10 }
                    var fact = facts[.database(kind, ref)] ?? PlaceFacts()
                    fact.monthlyMeanTemperatureC = months.count == 12 ? months : nil
                    fact.koppen = koppen
                    facts[.database(kind, ref)] = fact
                }
            }
        }
    }

    // swiftlint:enable function_body_length

    /// Every country's facts, keyed by ISO code. 252 rows, so it is read whole.
    func countryFacts() throws -> [String: CountryFacts] {
        let rows = try connection.query(
            """
            SELECT iso2, name, continent, capital, population, area_km2, currency_code,
                   languages, is_un_member, is_un_observer
            FROM country ORDER BY iso2
            """
        ) { row in
            try CountryFacts(
                code: row.requiredString(0),
                name: row.requiredString(1),
                continent: row.string(2).flatMap(Continent.init(rawValue:)),
                capitalName: row.string(3),
                population: row.int(4),
                areaKm2: row.double(5),
                currencyCode: row.string(6),
                languageCodes: (row.string(7) ?? "")
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                isUNMember: row.bool(8),
                isUNObserver: row.bool(9)
            )
        }
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.code, $0) })
    }

    /// The landmark theme taxonomy, in its curated order (R-DB-1).
    func themes() throws -> [ThemeDefinition] {
        try connection.query(
            "SELECT id, label, description FROM theme ORDER BY sort_order"
        ) { row in
            try ThemeDefinition(
                id: row.requiredString(0),
                label: row.requiredString(1),
                description: row.string(2)
            )
        }
    }

    /// Everything the statistics need from the database in one value, for the places
    /// in `ids` (decision D-2: the engine itself never opens the database).
    func gazetteer(for ids: some Sequence<PlaceID>) throws -> Gazetteer {
        try Gazetteer(places: facts(for: ids), countries: countryFacts(), themes: themes())
    }

    // MARK: - Collections and achievements

    /// The curated collections, each with its members resolved to full references
    /// (R-WISH-2).
    func collections() throws -> [CollectionDefinition] {
        let headers = try connection.query(
            "SELECT id, name, description, symbol FROM collection ORDER BY sort_order, id"
        ) { row in
            try (row.requiredString(0), row.requiredString(1), row.string(2), row.string(3))
        }
        var members: [String: [PlaceReference]] = [:]
        let rows = try connection.query(
            """
            SELECT cm.collection_id, \(Self.resultColumns)
            FROM collection_member AS cm
            JOIN place_index AS p ON p.kind = cm.place_kind AND p.ref_id = cm.ref_id
            ORDER BY cm.collection_id, cm.sort_order
            """
        ) { row in
            try (row.requiredString(0), Self.decodeSearchResult(row, offset: 1))
        }
        for (collection, result) in rows {
            members[collection, default: []].append(result.placeReference)
        }
        return headers.map { header in
            CollectionDefinition(
                id: header.0,
                name: header.1,
                description: header.2,
                symbol: header.3,
                members: members[header.0] ?? []
            )
        }
    }

    /// Achievement definitions in display order (R-ACH-1). A rule this build does not
    /// know comes back with `rule == nil`, for the caller to skip.
    func achievements() throws -> [AchievementDefinition] {
        try connection.query(
            """
            SELECT id, name, description, symbol, rule, threshold, parameter, tier,
                   sort_order
            FROM achievement ORDER BY sort_order, id
            """
        ) { row in
            try AchievementDefinition(
                id: row.requiredString(0),
                name: row.requiredString(1),
                description: row.requiredString(2),
                symbol: row.string(3),
                rule: AchievementRule(rawValue: row.requiredString(4)),
                threshold: row.double(5),
                parameter: row.string(6),
                tier: row.string(7).flatMap(AchievementTier.init(rawValue:)),
                sortOrder: row.int(8) ?? 0
            )
        }
    }

    // MARK: - Routes

    /// The route catalogue (R-JLOG-3), with each end resolved where it is a bundled
    /// place.
    func routes() throws -> [RouteInfo] {
        let rows = try connection.query(
            """
            SELECT id, name, mode, start_name, end_name, start_kind, start_ref_id,
                   end_kind, end_ref_id, country_codes, length_km,
                   typical_duration_minutes, highest_point_m
            FROM route ORDER BY name
            """
        ) { row in
            try RouteRow(
                id: row.requiredInt64(0),
                name: row.requiredString(1),
                mode: row.requiredString(2),
                startName: row.string(3),
                endName: row.string(4),
                start: Self.placeID(kind: row.string(5), row: row.int64(6)),
                end: Self.placeID(kind: row.string(7), row: row.int64(8)),
                countryCodes: row.string(9),
                lengthKm: row.double(10),
                durationMinutes: row.int(11),
                highestPointM: row.double(12)
            )
        }
        let ends = try places(for: rows.flatMap { [$0.start, $0.end].compactMap(\.self) })
        return rows.compactMap { route in
            guard let mode = TravelMode(rawValue: route.mode) else { return nil }
            return RouteInfo(
                id: route.id,
                name: route.name,
                mode: mode,
                startName: route.startName,
                endName: route.endName,
                start: route.start.flatMap { ends[$0]?.placeReference },
                end: route.end.flatMap { ends[$0]?.placeReference },
                countryCodes: (route.countryCodes ?? "")
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) },
                lengthKm: route.lengthKm,
                typicalDurationMinutes: route.durationMinutes,
                highestPointM: route.highestPointM
            )
        }
    }

    func route(id: Int64) throws -> RouteInfo? {
        try routes().first { $0.id == id }
    }

    // MARK: - Carbon

    /// The carbon factors and who published them (R-CO2-1, R-CO2-3).
    func emissionFactors() throws -> EmissionFactorTable {
        let factors = try connection.query(
            """
            SELECT mode, travel_class, kg_co2e_per_km, basis, label, year
            FROM emission_factor ORDER BY mode, travel_class
            """
        ) { row -> EmissionFactor? in
            guard let mode = try TravelMode(rawValue: row.requiredString(0)),
                  let basis = try EmissionBasis(rawValue: row.requiredString(3))
            else { return nil }
            return try EmissionFactor(
                mode: mode,
                travelClass: row.string(1) ?? "",
                kgCO2ePerKm: row.double(2) ?? 0,
                basis: basis,
                label: row.requiredString(4),
                year: row.int(5) ?? 0
            )
        }.compactMap(\.self)
        let source = try connection.queryOne(
            "SELECT name FROM data_source WHERE id = 'desnz'"
        ) { try $0.requiredString(0) }
        return EmissionFactorTable(factors: factors, sourceName: source ?? "")
    }

    // MARK: - Helpers

    private static func placeID(kind: String?, row: Int64?) -> PlaceID? {
        guard let kind = kind.flatMap(PlaceKind.init(rawValue:)), let row else { return nil }
        return .database(kind, row)
    }
}

private struct RouteRow {
    let id: Int64
    let name: String
    let mode: String
    let startName: String?
    let endName: String?
    let start: PlaceID?
    let end: PlaceID?
    let countryCodes: String?
    let lengthKm: Double?
    let durationMinutes: Int?
    let highestPointM: Double?
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
