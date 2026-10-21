import AntipodesCore
import Foundation

/// The railway network rail legs are measured along (R-PATH-2, R-PATH-5, D-30).
public extension PlaceDatabase {
    /// Every junction and stretch of track. About 20,000 junctions and 25,000 stretches,
    /// read once and kept by the caller: routing needs all of it in memory.
    func railNetwork() throws -> RailNetwork {
        let version = try connection.queryOne(
            "SELECT value FROM meta WHERE key = 'rail_network_version'"
        ) { try $0.requiredString(0) } ?? "unversioned"
        let nodes = try connection.query(
            "SELECT latitude, longitude FROM rail_node ORDER BY id"
        ) { row in
            Coordinate(latitude: row.double(0) ?? 0, longitude: row.double(1) ?? 0)
        }
        let edges = try connection.query(
            "SELECT node_a, node_b, length_m, points FROM rail_edge ORDER BY id"
        ) { row in
            // Ids start at 1; the network counts its nodes from 0.
            try RailEdge(
                a: Int(row.requiredInt64(0)) - 1,
                b: Int(row.requiredInt64(1)) - 1,
                lengthKm: Double(row.requiredInt64(2)) / 1000,
                points: Self.railPoints(row.blob(3) ?? Data())
            )
        }
        return RailNetwork(version: version, nodes: nodes, edges: edges)
    }

    /// Little-endian int32 pairs, latitude then longitude, in 1/100,000 of a degree.
    internal static func railPoints(_ blob: Data) -> [Coordinate] {
        let count = blob.count / 8
        return blob.withUnsafeBytes { raw in
            (0 ..< count).map { index in
                let latitude = Int32(littleEndian: raw.loadUnaligned(
                    fromByteOffset: index * 8,
                    as: Int32.self
                ))
                let longitude = Int32(
                    littleEndian: raw.loadUnaligned(fromByteOffset: index * 8 + 4, as: Int32.self)
                )
                return Coordinate(
                    latitude: Double(latitude) / 100_000,
                    longitude: Double(longitude) / 100_000
                )
            }
        }
    }
}
