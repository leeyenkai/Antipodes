@testable import AntipodesCore
import Testing

/// A small network on whole degrees near the equator, where one degree of latitude, and
/// of longitude along the equator, is 111.195 km (2πR / 360, R = 6,371.0088 km).
///
///     node 4 (2°N, 1°E)
///        |  e3, stored 4 → 3
///     node 3 (1°N, 1°E)
///        |  e2, stored 3 → 1
///     node 0 ——— e0 ——— node 1 ——— e1 ——— node 2        node 5 —— e4 —— node 6
///     (0, 0)            (0, 1°E)           (0, 2°E)       (10°N, 10°E)   (10°N, 11°E)
enum RailFixture {
    static let degree = 111.195

    static func at(_ latitude: Double, _ longitude: Double) -> Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    static let network = RailNetwork(
        version: "test",
        nodes: [at(0, 0), at(0, 1), at(0, 2), at(1, 1), at(2, 1), at(10, 10), at(10, 11)],
        edges: [
            RailEdge(a: 0, b: 1, lengthKm: degree, points: [at(0, 0), at(0, 0.5), at(0, 1)]),
            RailEdge(a: 1, b: 2, lengthKm: degree, points: [at(0, 1), at(0, 2)]),
            RailEdge(a: 3, b: 1, lengthKm: degree, points: [at(1, 1), at(0, 1)]),
            RailEdge(a: 4, b: 3, lengthKm: degree, points: [at(2, 1), at(1, 1)]),
            RailEdge(a: 5, b: 6, lengthKm: degree, points: [at(10, 10), at(10, 11)]),
        ]
    )
}

@Suite("Railway network")
struct RailNetworkTests {
    @Test("An end is joined to the nearest track, and the leg runs along it")
    func snapsAndRoutes() throws {
        // 0.05° north of the line at 0.2°E and 1.8°E: 5.560 km off the track at each end,
        // and 1.6° of track between, 177.912 km.
        let path = try #require(RailFixture.network.route(
            from: RailFixture.at(0.05, 0.2),
            to: RailFixture.at(0.05, 1.8)
        ))
        #expect(abs(path.lengthKm - (177.912 + 2 * 5.560)) < 0.01)
        #expect(path.coordinates == [
            RailFixture.at(0.05, 0.2),
            RailFixture.at(0, 0.2),
            RailFixture.at(0, 0.5),
            RailFixture.at(0, 1),
            RailFixture.at(0, 1.8),
            RailFixture.at(0.05, 1.8),
        ])
    }

    @Test("Edges are ridden either way, whichever way they were stored")
    func ridesEdgesBackwards() throws {
        let north = RailFixture.at(2, 1)
        let east = RailFixture.at(0, 2)
        // Three degrees of track, e3 and e2 forwards, then e1.
        let out = try #require(RailFixture.network.route(from: north, to: east))
        #expect(abs(out.lengthKm - 3 * RailFixture.degree) < 0.01)
        #expect(out.coordinates == [north, RailFixture.at(1, 1), RailFixture.at(0, 1), east])
        // And back: e1, then e2 and e3 against the way they were stored.
        let back = try #require(RailFixture.network.route(from: east, to: north))
        #expect(abs(back.lengthKm - 3 * RailFixture.degree) < 0.01)
        #expect(back.coordinates == out.coordinates.reversed())
    }

    @Test("Two ends on one stretch of track run straight along it")
    func sameEdge() throws {
        let path = try #require(RailFixture.network.route(
            from: RailFixture.at(0, 0.6),
            to: RailFixture.at(0, 0.1)
        ))
        #expect(abs(path.lengthKm - 0.5 * RailFixture.degree) < 0.01)
        #expect(path.coordinates == [
            RailFixture.at(0, 0.6),
            RailFixture.at(0, 0.5),
            RailFixture.at(0, 0.1),
        ])
    }

    @Test("No path when an end is far from track or the network does not join them")
    func noPath() {
        // 0.5° from the nearest track is 55.6 km, beyond the 25 km an end may be.
        #expect(RailFixture.network.route(
            from: RailFixture.at(0.5, 0.5),
            to: RailFixture.at(0, 2)
        ) == nil)
        // e4 is on its own.
        #expect(RailFixture.network.route(
            from: RailFixture.at(0, 0),
            to: RailFixture.at(10, 10.5)
        ) == nil)
        #expect(RailNetwork.empty
            .route(from: RailFixture.at(0, 0), to: RailFixture.at(0, 1)) == nil)
    }
}

@Suite("Countries along a railway")
struct RailCountriesTests {
    /// West of 1°E is AA, east of it BB, and a sliver 1.1 km wide between 1.00° and
    /// 1.01°E is CC. North of 5°N is sea.
    static func lookup(_ point: Coordinate) -> String? {
        if point.latitude > 5 {
            return nil
        }
        if point.longitude < 1 {
            return "AA"
        }
        if point.longitude < 1.01 {
            return "CC"
        }
        return "BB"
    }

    @Test("Each country is listed once, in the order the track reaches it")
    func countriesInOrder() {
        let path = RailPath(
            coordinates: [RailFixture.at(0, 0), RailFixture.at(0, 2)],
            lengthKm: 2 * RailFixture.degree
        )
        // The 1.1 km of CC is under the 3 km a run needs in the middle of a path.
        #expect(path.countries(lookup: Self.lookup) == ["AA", "BB"])
        // Sampled every 0.5 km with no bar, it is a country of its own.
        #expect(path.countries(sampleEveryKm: 0.5, ignoringRunsUnderKm: 0, lookup: Self.lookup)
            == ["AA", "CC", "BB"])
    }

    @Test("Points at sea are skipped, and a path back home is two crossings")
    func seaAndReturn() {
        let path = RailPath(
            coordinates: [
                RailFixture.at(0, 0.5), RailFixture.at(0, 1.5),
                RailFixture.at(6, 1.5), RailFixture.at(6, 0.6), RailFixture.at(0, 0.6),
            ],
            lengthKm: 1000
        )
        #expect(path.countries(lookup: Self.lookup) == ["AA", "BB", "AA"])
    }
}
