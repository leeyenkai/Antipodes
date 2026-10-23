import AntipodesCore
@testable import AntipodesPlaces
import Foundation
import SQLite3
import Testing

/// The route pack read from a small one built here from the pipeline's own schema, so
/// the tests need neither the network nor the real pack (D-36).
@Suite("Route pack")
struct RoutePackTests {
    static let schema = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Tools/osmpack/schema.sql")

    /// Two points 0.1° apart along the equator, in the pack's encoding.
    static let segmentBlob = "X'000000000000000000001027' || X'0000'"

    /// Every line here is the same: two points 0.1° apart along the equator, in the
    /// pack's encoding (an int32 pair, then one int16 step).
    static func makePack(schemaVersion: Int = 1) throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appending(path: "routes-osm-\(UUID().uuidString).sqlite").path
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK else { throw SQLiteError.cannotOpen(
            path: path,
            message: ""
        ) }
        defer { sqlite3_close(handle) }
        let statements = try String(contentsOf: schema, encoding: .utf8) + """
        INSERT INTO meta VALUES ('schema_version', '\(
            schemaVersion
        )'), ('network_version', 'osm-2026-10-23'),
            ('attribution', '© OpenStreetMap contributors'), ('osm_snapshot', '2026-10-23');
        INSERT INTO track_region
            VALUES ('hiking/alps', 'hiking', 'alps', 'The Alps', 43.6, 5, 48.4, 16.9);
        INSERT INTO track_edge VALUES ('hiking/alps', 1, 1, 2, 11132, X'000000000000000000001027');
        INSERT INTO route_shape VALUES (4, 0, 11132, X'000000000000000000001027');
        INSERT INTO aerialway
            VALUES (7, 'gondola', 'Test lift', 'Bottom', 'Top', 0, 0, 0, 0.1, 11132,
            X'000000000000000000001027');
        INSERT INTO transit_system
            VALUES (3000000000001, 'NYC Subway', 'metro', 'New York', 'US', 'osm-2026-10-23');
        INSERT INTO transit_line VALUES (1000000000042, 3000000000001, 'A', 'A', '0039A6', 1);
        INSERT INTO transit_stop VALUES
            (2000000000001, 'Inwood', 40.868, -73.919), (2000000000002, 'Dyckman', 40.865, -73.927);
        INSERT INTO transit_segment VALUES (1000000000042, 2000000000001, 2000000000002);
        INSERT INTO transit_shape VALUES
            (1000000000042, 0, X'000000000000000000001027'), (2944, 0, X'000000000000000000001027');
        """
        guard sqlite3_exec(handle, statements, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.cannotOpen(
                path: path,
                message: String(cString: sqlite3_errmsg(handle))
            )
        }
        return path
    }

    @Test("A pack opens, says what it is, and reads each kind of thing")
    func reads() async throws {
        let pack = try RoutePack(path: Self.makePack())
        #expect(pack.networkVersion == "osm-2026-10-23")

        let regions = try await pack.trailRegions()
        #expect(regions.map(\.network) == ["hiking/alps"])
        let network = try await pack.trailNetwork(regions[0])
        #expect(network.kind == .hiking)
        #expect(network.edges.count == 1)

        #expect(try await pack.routeShape(4).first?.count == 2)
        #expect(try await pack.shapedRoutes() == [4])

        let lifts = try await pack.lifts(
            near: Coordinate(latitude: 0, longitude: 0.01),
            withinKm: 2
        )
        #expect(lifts.map(\.name) == ["Test lift"])
        #expect(try await pack.liftNetwork().edges.count == 1)

        let systems = try await pack.transitSystems()
        #expect(systems.map(\.name) == ["NYC Subway"])
        let transit = try await pack.transitNetwork(systems: [3_000_000_000_001])
        #expect(transit.lines.count == 1)
        #expect(transit.stops.count == 2)
        // A place-database line (Q2944) gets its shape from the pack too.
        let shapes = try await pack.transitShapes(lines: [1_000_000_000_042, 2944])
        #expect(shapes.keys.sorted() == [2944, 1_000_000_000_042])
    }

    @Test("A pack of another schema version is refused, not misread")
    func schemaVersion() throws {
        #expect(throws: PlaceDatabaseError.self) {
            _ = try RoutePack(path: Self.makePack(schemaVersion: 99))
        }
    }
}
