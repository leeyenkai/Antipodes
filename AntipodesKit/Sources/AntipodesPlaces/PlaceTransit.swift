import AntipodesCore
import Foundation

/// City transit systems, lines and stops (R-TRAN-1 to R-TRAN-5).
public extension PlaceDatabase {
    /// Every system in the database, by name: the first step of logging a ride
    /// (R-JLOG-5).
    func transitSystems() throws -> [TransitSystemInfo] {
        try connection.query(
            """
            SELECT s.id, s.name, s.kind, c.name, s.country_iso2, s.network_version
            FROM transit_system AS s LEFT JOIN city AS c ON c.id = s.city_id
            ORDER BY s.name
            """
        ) { row in
            try TransitSystemInfo(
                id: row.requiredInt64(0),
                name: row.requiredString(1),
                kind: row.requiredString(2),
                cityName: row.string(3),
                countryCode: row.requiredString(4),
                networkVersion: row.requiredString(5)
            )
        }
    }

    /// The systems the given lines belong to.
    func transitSystems(ofLines lines: Set<Int64>) throws -> Set<Int64> {
        var systems: Set<Int64> = []
        for chunk in lines.sorted().chunked(into: 400) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            try systems.formUnion(connection.query(
                "SELECT DISTINCT system_id FROM transit_line WHERE id IN (\(placeholders))",
                parameters: chunk.map { .integer($0) }
            ) { try $0.requiredInt64(0) })
        }
        return systems
    }

    /// Every line, stop and segment of the given systems: what routing a ride and
    /// measuring a network need.
    func transitNetwork(systems ids: Set<Int64>) throws -> TransitNetwork {
        guard !ids.isEmpty else { return .empty }
        let all = try transitSystems()
        let systems = Dictionary(uniqueKeysWithValues: all.filter { ids.contains($0.id) }.map {
            ($0.id, $0)
        })
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let parameters: [SQLiteValue] = ids.sorted().map { .integer($0) }
        let lines = try connection.query(
            """
            SELECT id, system_id, name, short_name, colour FROM transit_line
            WHERE system_id IN (\(placeholders)) ORDER BY id
            """,
            parameters: parameters
        ) { row in
            try TransitLineInfo(
                id: row.requiredInt64(0),
                systemID: row.requiredInt64(1),
                name: row.requiredString(2),
                shortName: row.string(3),
                colour: row.string(4)
            )
        }
        let segments = try connection.query(
            """
            SELECT g.line_id, g.stop_a, g.stop_b FROM transit_segment AS g
            JOIN transit_line AS l ON l.id = g.line_id
            WHERE l.system_id IN (\(placeholders))
            """,
            parameters: parameters
        ) { row in
            try TransitSegment(
                lineID: row.requiredInt64(0),
                between: row.requiredInt64(1),
                and: row.requiredInt64(2)
            )
        }
        let stops = try transitStops(Set(segments.flatMap { [$0.first, $0.second] }))
        return TransitNetwork(
            systems: systems,
            lines: Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) }),
            stops: stops,
            segments: segments
        )
    }

    private func transitStops(_ ids: Set<Int64>) throws -> [Int64: TransitStop] {
        var stops: [Int64: TransitStop] = [:]
        for chunk in ids.sorted().chunked(into: 400) {
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            for stop in try connection.query(
                "SELECT id, name, latitude, longitude FROM transit_stop WHERE id IN (\(marks))",
                parameters: chunk.map { .integer($0) },
                row: { row in
                    try TransitStop(
                        id: row.requiredInt64(0),
                        name: row.requiredString(1),
                        coordinate: Coordinate(
                            latitude: row.double(2) ?? 0,
                            longitude: row.double(3) ?? 0
                        )
                    )
                }
            ) {
                stops[stop.id] = stop
            }
        }
        return stops
    }

    /// A stop as a place a leg can start or end at: a station, in its system's city.
    func transitStopPlace(id: Int64) throws -> PlaceReference? {
        try connection.queryOne(
            """
            SELECT s.id, s.name, s.latitude, s.longitude, s.country_iso2, n.name, n.continent,
                   s.city_id, c.name, s.timezone
            FROM transit_stop AS s
            LEFT JOIN country AS n ON n.iso2 = s.country_iso2
            LEFT JOIN city AS c ON c.id = s.city_id
            WHERE s.id = ?
            """,
            parameters: [.integer(id)]
        ) { row in
            try PlaceReference(
                id: .database(.station, row.requiredInt64(0)),
                kind: .station,
                name: row.requiredString(1),
                coordinate: Coordinate(latitude: row.double(2) ?? 0, longitude: row.double(3) ?? 0),
                countryCode: row.string(4),
                countryName: row.string(5),
                continent: row.string(6).flatMap(Continent.init(rawValue:)),
                cityID: row.int64(7),
                cityName: row.string(8),
                timeZoneIdentifier: row.string(9)
            )
        }
    }
}
