import AntipodesCore
import Foundation

/// The networks surface legs are measured along (R-PATH-2, R-PATH-5, D-30).
public extension PlaceDatabase {
    /// One network whole: tens of thousands of edges, read once and kept by the caller,
    /// because routing needs all of it in memory.
    func trackNetwork(_ kind: TrackKind) throws -> TrackNetwork {
        let version = try connection.queryOne(
            "SELECT value FROM meta WHERE key = 'track_network_version'"
        ) { try $0.requiredString(0) } ?? "unversioned"
        let edges = try connection.query(
            """
            SELECT node_a, node_b, length_m, points FROM track_edge
            WHERE network = ? ORDER BY id
            """,
            parameters: [.text(kind.rawValue)]
        ) { row in
            // Ids start at 1; the network counts its nodes from 0.
            try TrackEdge(
                a: Int(row.requiredInt64(0)) - 1,
                b: Int(row.requiredInt64(1)) - 1,
                lengthKm: Double(row.requiredInt64(2)) / 1000,
                points: Self.trackPoints(row.blob(3) ?? Data())
            )
        }
        // A junction is where its edges' ends are.
        let count = edges.reduce(0) { max($0, $1.a + 1, $1.b + 1) }
        var nodes = Array(repeating: Coordinate(latitude: 0, longitude: 0), count: count)
        for edge in edges {
            if let first = edge.points.first, let last = edge.points.last {
                nodes[edge.a] = first
                nodes[edge.b] = last
            }
        }
        return TrackNetwork(kind: kind, version: version, nodes: nodes, edges: edges)
    }

    /// The first point as two little-endian int32, latitude then longitude, in
    /// 1/100,000 of a degree; then each point as two int16 steps from the one before.
    internal static func trackPoints(_ blob: Data) -> [Coordinate] {
        guard blob.count >= 8 else { return [] }
        return blob.withUnsafeBytes { raw in
            var latitude = Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 0, as: Int32.self))
            var longitude = Int32(littleEndian: raw.loadUnaligned(
                fromByteOffset: 4,
                as: Int32.self
            ))
            var points = [Self.coordinate(latitude, longitude)]
            points.reserveCapacity(1 + (blob.count - 8) / 4)
            var offset = 8
            while offset + 4 <= blob.count {
                latitude += Int32(Int16(littleEndian: raw.loadUnaligned(
                    fromByteOffset: offset,
                    as: Int16.self
                )))
                longitude += Int32(
                    Int16(littleEndian: raw.loadUnaligned(
                        fromByteOffset: offset + 2,
                        as: Int16.self
                    ))
                )
                points.append(Self.coordinate(latitude, longitude))
                offset += 4
            }
            return points
        }
    }

    private static func coordinate(_ latitude: Int32, _ longitude: Int32) -> Coordinate {
        Coordinate(latitude: Double(latitude) / 100_000, longitude: Double(longitude) / 100_000)
    }
}
