import AntipodesCore
import Foundation

// Where on the map things are, for places that come without a database identity: a
// dropped pin, a photo, the city behind an airport. Read-only and identical for every
// user (R-PRIV-3); nothing here leaves the device.

public extension PlaceDatabase {
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

    /// The country's time zone, when every bundled city in it keeps the same one —
    /// the rule D-13 uses for airports and landmarks. A country spanning zones has no
    /// answer here rather than a guess.
    func singleTimeZone(country code: String) throws -> String? {
        let zones = try connection.query(
            """
            SELECT DISTINCT timezone FROM city
            WHERE country_iso2 = ? AND timezone IS NOT NULL
            LIMIT 2
            """,
            parameters: [.text(code.uppercased())]
        ) { row in row.string(0) }
        return zones.count == 1 ? zones[0] : nil
    }

    /// The city an airport serves, for logging where a flight arrived (D-32).
    ///
    /// OurAirports links many airports to no bundled city — JFK, Charles de Gaulle,
    /// Helsinki-Vantaa — so the link is used where it exists, then the city its own
    /// municipality names ("Helsinki (Vantaa)" → Helsinki, "New York" → New York City)
    /// within 100 km in the same country, then the bundled city that most outweighs its
    /// distance within 60 km — Paris over Roissy. `nil` where nothing is near.
    func city(servingAirport airportID: Int64) throws -> PlaceSearchResult? {
        guard let airport = try connection.queryOne(
            """
            SELECT city_id, city_name, country_iso2, latitude, longitude
            FROM airport WHERE id = ?
            """,
            parameters: [.integer(airportID)],
            row: { row in
                try (
                    cityID: row.int64(0),
                    cityName: row.string(1),
                    country: row.requiredString(2),
                    at: Coordinate(latitude: row.double(3) ?? 0, longitude: row.double(4) ?? 0)
                )
            }
        ) else { return nil }
        if let cityID = airport.cityID {
            return try place(kind: .city, id: cityID)
        }
        let nearby = try connection.query(
            """
            SELECT id, name, ascii_name, latitude, longitude, population FROM city
            WHERE country_iso2 = ? AND latitude BETWEEN ? AND ?
            """,
            parameters: [
                .text(airport.country),
                .double(airport.at.latitude - 1),
                .double(airport.at.latitude + 1),
            ]
        ) { row in
            try (
                id: row.requiredInt64(0),
                names: [row.string(1), row.string(2)].compactMap { $0?.lowercased() },
                distanceKm: GreatCircle.distanceKm(
                    from: airport.at,
                    to: Coordinate(latitude: row.double(3) ?? 0, longitude: row.double(4) ?? 0)
                ),
                population: Double(row.int64(5) ?? 0)
            )
        }
        let named = airport.cityName?
            .split(whereSeparator: { $0 == "(" || $0 == "," })
            .first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        // The city of that name, nearest first; failing that, the biggest whose name
        // begins with it — "New York" is New York City, where "Paris" must not become
        // the nearer "Paris 19 Buttes-Chaumont".
        if let named, !named.isEmpty {
            let near = nearby.filter { $0.distanceKm <= 100 }
            let exact = near.filter { $0.names.contains(named) }
                .min { $0.distanceKm < $1.distanceKm }
            let longer = near.filter { $0.names.contains { $0.hasPrefix(named + " ") } }
                .max { $0.population < $1.population }
            if let match = exact ?? longer {
                return try place(kind: .city, id: match.id)
            }
        }
        let weighed = nearby.filter { $0.distanceKm <= 60 }
            .max { first, second in
                first.population / pow(first.distanceKm + 5, 2)
                    < second.population / pow(second.distanceKm + 5, 2)
            }
        return try weighed.flatMap { try place(kind: .city, id: $0.id) }
    }
}
