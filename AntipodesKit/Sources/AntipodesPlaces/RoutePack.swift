import AntipodesCore
import Foundation

/// The OpenStreetMap route pack (D-36): trail networks, catalogue route shapes, aerial
/// lifts and city transit lines with their shapes, in a read-only file of its own
/// beside the place database.
///
/// It is a separate file because OpenStreetMap is under the ODbL, whose share-alike
/// terms reach the database its data is in (D-8): kept apart, they reach this file and
/// nothing else. The app works without it — every caller falls back to what it did
/// before the pack existed — so a build without the pack still runs.
public actor RoutePack {
    public static let expectedSchemaVersion = 1

    let connection: SQLiteConnection
    // SwiftFormat and SwiftLint disagree on the order of these modifiers.
    // swiftlint:disable modifier_order
    public nonisolated let path: String
    /// The version every transit ride and measured leg from this pack records.
    public nonisolated let networkVersion: String
    /// "© OpenStreetMap contributors, …", as the licence asks it to be shown.
    public nonisolated let attribution: String
    /// The day or days the map was read.
    public nonisolated let snapshot: String
    // swiftlint:enable modifier_order

    public init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw PlaceDatabaseError.fileMissing(path: path)
        }
        connection = try SQLiteConnection(readOnlyPath: path)
        self.path = path
        var meta: [String: String] = [:]
        for (key, value) in try connection.query("SELECT key, value FROM meta", row: {
            try ($0.requiredString(0), $0.requiredString(1))
        }) {
            meta[key] = value
        }
        let version = meta["schema_version"].flatMap(Int.init) ?? 0
        guard version == Self.expectedSchemaVersion else {
            throw PlaceDatabaseError.schemaMismatch(
                found: version,
                expected: Self.expectedSchemaVersion
            )
        }
        networkVersion = meta["network_version"] ?? "osm"
        attribution = meta["attribution"] ?? "© OpenStreetMap contributors"
        snapshot = meta["osm_snapshot"] ?? ""
    }

    // MARK: - Trails

    /// Every region's hiking and cycling network, without its edges.
    public func trailRegions() throws -> [TrailRegion] {
        try connection.query(
            """
            SELECT network, kind, name, south, west, north, east FROM track_region
            ORDER BY network
            """
        ) { row in
            let kind = try TrackKind(rawValue: row.requiredString(1)) ?? .hiking
            return try TrailRegion(
                network: row.requiredString(0),
                kind: kind,
                name: row.requiredString(2),
                south: row.double(3) ?? 0,
                west: row.double(4) ?? 0,
                north: row.double(5) ?? 0,
                east: row.double(6) ?? 0
            )
        }
    }

    /// One region's network whole, for routing on.
    public func trailNetwork(_ region: TrailRegion) throws -> TrackNetwork {
        let edges = try connection.query(
            "SELECT node_a, node_b, length_m, points FROM track_edge WHERE network = ? ORDER BY id",
            parameters: [.text(region.network)]
        ) { row in
            try TrackEdge(
                a: Int(row.requiredInt64(0)) - 1,
                b: Int(row.requiredInt64(1)) - 1,
                lengthKm: Double(row.requiredInt64(2)) / 1000,
                points: PlaceDatabase.trackPoints(row.blob(3) ?? Data())
            )
        }
        let count = edges.reduce(0) { max($0, $1.a + 1, $1.b + 1) }
        var nodes = Array(repeating: Coordinate(latitude: 0, longitude: 0), count: count)
        for edge in edges {
            if let first = edge.points.first, let last = edge.points.last {
                nodes[edge.a] = first
                nodes[edge.b] = last
            }
        }
        return TrackNetwork(kind: region.kind, version: networkVersion, nodes: nodes, edges: edges)
    }

    // MARK: - Catalogue routes

    /// A catalogue route's real shape, in pieces where the map has gaps (R-JLOG-3).
    public func routeShape(_ routeID: Int64) throws -> [[Coordinate]] {
        try connection.query(
            "SELECT points FROM route_shape WHERE route_id = ? ORDER BY part",
            parameters: [.integer(routeID)]
        ) { PlaceDatabase.trackPoints($0.blob(0) ?? Data()) }
    }

    /// Which catalogue routes have a shape.
    public func shapedRoutes() throws -> Set<Int64> {
        try Set(connection
            .query("SELECT DISTINCT route_id FROM route_shape") { try $0.requiredInt64(0) })
    }

    // MARK: - Lifts

    /// Every lift, as the network cable-car legs are measured along (D-36).
    public func liftNetwork() throws -> TrackNetwork {
        let lifts = try connection.query(
            """
            SELECT id, kind, name, start_name, end_name, length_m, points FROM aerialway
            ORDER BY id
            """
        ) { row in
            try AerialLift(
                id: row.requiredInt64(0),
                kind: row.requiredString(1),
                name: row.string(2),
                startName: row.string(3),
                endName: row.string(4),
                lengthKm: Double(row.requiredInt64(5)) / 1000,
                points: PlaceDatabase.trackPoints(row.blob(6) ?? Data())
            )
        }
        return AerialLift.network(lifts, version: networkVersion)
    }

    /// Lifts with a station within `withinKm` of a place.
    public func lifts(near place: Coordinate, withinKm: Double = 5) throws -> [AerialLift] {
        let degrees = withinKm / 111
        let low = place.latitude - degrees, high = place.latitude + degrees
        let lifts = try connection.query(
            """
            SELECT id, kind, name, start_name, end_name, length_m, points FROM aerialway
            WHERE start_lat BETWEEN ? AND ? OR end_lat BETWEEN ? AND ?
            """,
            parameters: [.double(low), .double(high), .double(low), .double(high)]
        ) { row in
            try AerialLift(
                id: row.requiredInt64(0),
                kind: row.requiredString(1),
                name: row.string(2),
                startName: row.string(3),
                endName: row.string(4),
                lengthKm: Double(row.requiredInt64(5)) / 1000,
                points: PlaceDatabase.trackPoints(row.blob(6) ?? Data())
            )
        }
        return lifts.filter { lift in
            [lift.start, lift.end].compactMap(\.self).contains {
                GreatCircle.distanceKm(from: place, to: $0) <= withinKm
            }
        }
    }

    // MARK: - City transit

    /// Every system in the pack (R-TRAN-5, R-TRAN-6).
    public func transitSystems() throws -> [TransitSystemInfo] {
        try connection.query(
            """
            SELECT id, name, kind, city_name, country_iso2, network_version
            FROM transit_system ORDER BY name
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

    /// Lines, stops and segments of the given systems, those the pack has.
    public func transitNetwork(systems ids: Set<Int64>) throws -> TransitNetwork {
        let mine = try transitSystems().filter { ids.contains($0.id) }
        guard !mine.isEmpty else { return .empty }
        let marks = Array(repeating: "?", count: mine.count).joined(separator: ",")
        let parameters: [SQLiteValue] = mine.map { .integer($0.id) }
        let lines = try connection.query(
            """
            SELECT id, system_id, name, short_name, colour FROM transit_line
            WHERE system_id IN (\(marks))
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
            JOIN transit_line AS l ON l.id = g.line_id WHERE l.system_id IN (\(marks))
            """,
            parameters: parameters
        ) { row in
            try TransitSegment(
                lineID: row.requiredInt64(0),
                between: row.requiredInt64(1),
                and: row.requiredInt64(2)
            )
        }
        var stops: [Int64: TransitStop] = [:]
        let wanted = Set(segments.flatMap { [$0.first, $0.second] })
        for chunk in wanted.sorted().chunked(into: 400) {
            let stopMarks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            for stop in try connection.query(
                "SELECT id, name, latitude, longitude FROM transit_stop WHERE id IN (\(stopMarks))",
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
        return TransitNetwork(
            systems: Dictionary(uniqueKeysWithValues: mine.map { ($0.id, $0) }),
            lines: Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0) }),
            stops: stops,
            segments: segments
        )
    }

    /// The systems the given lines belong to, of those in the pack.
    public func transitSystems(ofLines lines: Set<Int64>) throws -> Set<Int64> {
        var systems: Set<Int64> = []
        for chunk in lines.sorted().chunked(into: 400) {
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            try systems.formUnion(connection.query(
                "SELECT DISTINCT system_id FROM transit_line WHERE id IN (\(marks))",
                parameters: chunk.map { .integer($0) }
            ) { try $0.requiredInt64(0) })
        }
        return systems
    }

    /// The drawn shape of each line, for lines from the pack and for the place
    /// database's own lines the pack has a shape for.
    public func transitShapes(lines: Set<Int64>) throws -> [Int64: [[Coordinate]]] {
        var shapes: [Int64: [[Coordinate]]] = [:]
        for chunk in lines.sorted().chunked(into: 400) {
            let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
            for (line, points) in try connection.query(
                """
                SELECT line_id, points FROM transit_shape WHERE line_id IN (\(marks))
                ORDER BY line_id, part
                """,
                parameters: chunk.map { .integer($0) },
                row: { try ($0.requiredInt64(0), PlaceDatabase.trackPoints($0.blob(1) ?? Data())) }
            ) {
                shapes[line, default: []].append(points)
            }
        }
        return shapes
    }
}
