import AntipodesCore
@testable import AntipodesPlaces
import Foundation
import Testing

/// The bundled railway network (D-30), against the built database: real journeys must
/// come out near their published lengths.
@Suite("Railway network in the database", .enabled(if: PlaceDatabaseFixture.exists))
struct PlaceRailwayTests {
    static func at(_ latitude: Double, _ longitude: Double) -> Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    @Test("The network loads with its version")
    func loads() async throws {
        let network = try await PlaceDatabaseFixture.open().railNetwork()
        #expect(network.version == "naturalearth-v5.1.2")
        #expect(network.nodes.count > 15000)
        #expect(network.edges.count > 20000)
    }

    /// Published lengths: London King's Cross to Edinburgh Waverley is 632 km by the
    /// East Coast Main Line; Tokyo to Kyoto 476 km by the Tōkaidō Shinkansen. The
    /// network is drawn at 1:10m, so a few per cent either way is expected.
    @Test("Real journeys measure near their published lengths")
    func realJourneys() async throws {
        let network = try await PlaceDatabaseFixture.open().railNetwork()
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
    }

    @Test("No railway crosses the Atlantic")
    func noPathAcrossTheSea() async throws {
        let network = try await PlaceDatabaseFixture.open().railNetwork()
        #expect(network
            .route(from: Self.at(51.5074, -0.1278), to: Self.at(40.7128, -74.006)) == nil)
    }

    @Test("Track points decode from their stored integers")
    func decodesPoints() {
        var blob = Data()
        for value: Int32 in [5_991_087, 1_075_245, -3_386_882, 15_120_929] {
            withUnsafeBytes(of: value.littleEndian) { blob.append(contentsOf: $0) }
        }
        #expect(PlaceDatabase.railPoints(blob) == [
            Self.at(59.91087, 10.75245),
            Self.at(-33.86882, 151.20929),
        ])
    }
}
