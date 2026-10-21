import AntipodesCore
@testable import AntipodesPlaces
import Foundation
import Testing

/// The bundled railway, road and ferry networks (D-30), against the built database:
/// real journeys must come out near their published lengths.
@Suite("Track networks in the database", .enabled(if: PlaceDatabaseFixture.exists))
struct PlaceTrackTests {
    static func at(_ latitude: Double, _ longitude: Double) -> Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    @Test("Each network loads with its version, its junctions where its edges end")
    func loads() async throws {
        let database = try PlaceDatabaseFixture.open()
        let rail = try await database.trackNetwork(.rail)
        #expect(rail.version == "naturalearth-v5.1.2")
        #expect(rail.nodes.count > 15000)
        #expect(rail.edges.count > 20000)
        let edge = try #require(rail.edges.first)
        #expect(rail.nodes[edge.a] == edge.points.first)
        #expect(rail.nodes[edge.b] == edge.points.last)
        #expect(try await database.trackNetwork(.road).edges.count > 50000)
        #expect(try await database.trackNetwork(.ferry).edges.count > 500)
    }

    /// Published lengths: London King's Cross to Edinburgh Waverley is 632 km by the
    /// East Coast Main Line; Tokyo to Kyoto 476 km by the Tōkaidō Shinkansen. The
    /// network is drawn at 1:10m, so a few per cent either way is expected.
    @Test("Real train journeys measure near their published lengths")
    func railJourneys() async throws {
        let network = try await PlaceDatabaseFixture.open().trackNetwork(.rail)
        let london = try #require(network.route(
            from: Self.at(51.5074, -0.1278),
            to: Self.at(55.9533, -3.1883)
        ))
        #expect(london.lengthKm > 600 && london.lengthKm < 680)
        let tokyo = try #require(network.route(
            from: Self.at(35.6812, 139.7671),
            to: Self.at(34.9858, 135.7681)
        ))
        #expect(tokyo.lengthKm > 450 && tokyo.lengthKm < 520)
        // The path starts and ends at the places themselves.
        #expect(tokyo.coordinates.first == Self.at(35.6812, 139.7671))
        #expect(tokyo.coordinates.last == Self.at(34.9858, 135.7681))
        #expect(network
            .route(from: Self.at(51.5074, -0.1278), to: Self.at(40.7128, -74.006)) == nil)
    }

    /// Paris to Lyon is 465 km by the A6; Los Angeles to San Francisco 615 km by I-5.
    /// Natural Earth's roads are generalised, so they run a little short.
    @Test("Real drives measure near their published lengths")
    func roadJourneys() async throws {
        let network = try await PlaceDatabaseFixture.open().trackNetwork(.road)
        let france = try #require(network.route(
            from: Self.at(48.8566, 2.3522),
            to: Self.at(45.7640, 4.8357)
        ))
        #expect(france.lengthKm > 420 && france.lengthKm < 520)
        let california = try #require(network.route(
            from: Self.at(34.0522, -118.2437),
            to: Self.at(37.7749, -122.4194)
        ))
        #expect(california.lengthKm > 560 && california.lengthKm < 700)
        // Bergen to Ålesund takes ferries Natural Earth does not have; the way round
        // without them is three times the crow's, so the leg keeps its straight line.
        #expect(network.route(from: Self.at(60.3913, 5.3221), to: Self.at(62.4722, 6.1495)) == nil)
    }

    @Test("Track points decode from a first point and 16-bit steps")
    func decodesPoints() {
        var blob = Data()
        for value: Int32 in [5_991_087, 1_075_245] {
            withUnsafeBytes(of: value.littleEndian) { blob.append(contentsOf: $0) }
        }
        for value: Int16 in [-1087, 4755, 1000, -1000] {
            withUnsafeBytes(of: value.littleEndian) { blob.append(contentsOf: $0) }
        }
        #expect(PlaceDatabase.trackPoints(blob) == [
            Self.at(59.91087, 10.75245),
            Self.at(59.9, 10.8),
            Self.at(59.91, 10.79),
        ])
    }
}
