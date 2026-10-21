@testable import AntipodesCore
import Foundation
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
enum TrackFixture {
    static let degree = 111.195

    static func at(_ latitude: Double, _ longitude: Double) -> Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    static let network = TrackNetwork(
        kind: .rail,
        version: "test",
        nodes: [at(0, 0), at(0, 1), at(0, 2), at(1, 1), at(2, 1), at(10, 10), at(10, 11)],
        edges: [
            TrackEdge(a: 0, b: 1, lengthKm: degree, points: [at(0, 0), at(0, 0.5), at(0, 1)]),
            TrackEdge(a: 1, b: 2, lengthKm: degree, points: [at(0, 1), at(0, 2)]),
            TrackEdge(a: 3, b: 1, lengthKm: degree, points: [at(1, 1), at(0, 1)]),
            TrackEdge(a: 4, b: 3, lengthKm: degree, points: [at(2, 1), at(1, 1)]),
            TrackEdge(a: 5, b: 6, lengthKm: degree, points: [at(10, 10), at(10, 11)]),
        ]
    )
}

@Suite("Track network")
struct TrackNetworkTests {
    @Test("An end is joined to the nearest track, and the leg runs along it")
    func snapsAndRoutes() throws {
        // 0.05° north of the line at 0.2°E and 1.8°E: 5.560 km off the track at each end,
        // and 1.6° of track between, 177.912 km.
        let path = try #require(TrackFixture.network.route(
            from: TrackFixture.at(0.05, 0.2),
            to: TrackFixture.at(0.05, 1.8)
        ))
        #expect(abs(path.lengthKm - (177.912 + 2 * 5.560)) < 0.01)
        #expect(path.coordinates == [
            TrackFixture.at(0.05, 0.2),
            TrackFixture.at(0, 0.2),
            TrackFixture.at(0, 0.5),
            TrackFixture.at(0, 1),
            TrackFixture.at(0, 1.8),
            TrackFixture.at(0.05, 1.8),
        ])
    }

    @Test("Edges are ridden either way, whichever way they were stored")
    func ridesEdgesBackwards() throws {
        let north = TrackFixture.at(2, 1)
        let east = TrackFixture.at(0, 2)
        // Three degrees of track, e3 and e2 forwards, then e1.
        let out = try #require(TrackFixture.network.route(from: north, to: east))
        #expect(abs(out.lengthKm - 3 * TrackFixture.degree) < 0.01)
        #expect(out.coordinates == [north, TrackFixture.at(1, 1), TrackFixture.at(0, 1), east])
        // And back: e1, then e2 and e3 against the way they were stored.
        let back = try #require(TrackFixture.network.route(from: east, to: north))
        #expect(abs(back.lengthKm - 3 * TrackFixture.degree) < 0.01)
        #expect(back.coordinates == out.coordinates.reversed())
    }

    @Test("Two ends on one stretch of track run straight along it")
    func sameEdge() throws {
        let path = try #require(TrackFixture.network.route(
            from: TrackFixture.at(0, 0.6),
            to: TrackFixture.at(0, 0.1)
        ))
        #expect(abs(path.lengthKm - 0.5 * TrackFixture.degree) < 0.01)
        #expect(path.coordinates == [
            TrackFixture.at(0, 0.6),
            TrackFixture.at(0, 0.5),
            TrackFixture.at(0, 0.1),
        ])
    }

    @Test("No path when an end is far from track or the network does not join them")
    func noPath() {
        // 0.5° from the nearest track is 55.6 km, beyond the 25 km an end may be.
        #expect(TrackFixture.network.route(
            from: TrackFixture.at(0.5, 0.5),
            to: TrackFixture.at(0, 2)
        ) == nil)
        // e4 is on its own.
        #expect(TrackFixture.network.route(
            from: TrackFixture.at(0, 0),
            to: TrackFixture.at(10, 10.5)
        ) == nil)
        #expect(TrackNetwork.empty
            .route(from: TrackFixture.at(0, 0), to: TrackFixture.at(0, 1)) == nil)
    }
}

@Suite("Countries along a track")
struct TrackCountriesTests {
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
        let path = TrackPath(
            coordinates: [TrackFixture.at(0, 0), TrackFixture.at(0, 2)],
            lengthKm: 2 * TrackFixture.degree
        )
        // The 1.1 km of CC is under the 3 km a run needs in the middle of a path.
        #expect(path.countries(lookup: Self.lookup) == ["AA", "BB"])
        // Sampled every 0.5 km with no bar, it is a country of its own.
        #expect(path.countries(sampleEveryKm: 0.5, ignoringRunsUnderKm: 0, lookup: Self.lookup)
            == ["AA", "CC", "BB"])
    }

    @Test("Points at sea are skipped, and a path back home is two crossings")
    func seaAndReturn() {
        let path = TrackPath(
            coordinates: [
                TrackFixture.at(0, 0.5), TrackFixture.at(0, 1.5),
                TrackFixture.at(6, 1.5), TrackFixture.at(6, 0.6), TrackFixture.at(0, 0.6),
            ],
            lengthKm: 1000
        )
        #expect(path.countries(lookup: Self.lookup) == ["AA", "BB", "AA"])
    }
}

@Suite("Which legs are measured")
struct TrackMeasurementTests {
    @Test("Rail, road and ferry legs with no length of their own are measured")
    func measuredModes() {
        #expect(TravelMode.rail.trackKind == .rail)
        #expect(TravelMode.coach.trackKind == .road)
        #expect(TravelMode.roadTrip.trackKind == .road)
        #expect(TravelMode.ferry.trackKind == .ferry)
        #expect(TravelMode.flight.trackKind == nil)
        #expect(TravelMode.humanPowered.trackKind == nil)

        let place = PlaceReference(id: .custom(UUID()), kind: .custom, name: "A")
        var leg = JourneyLeg(mode: .coach, origin: place, destination: place)
        #expect(leg.needsTrackMeasurement)
        leg.distanceKmOverride = 12
        #expect(!leg.needsTrackMeasurement)
        leg.distanceKmOverride = nil
        leg.storedPathLengthKm = 40
        #expect(!leg.needsTrackMeasurement)
        // A catalogue route's length is not the map's.
        #expect(!leg.isMeasuredAlongTrack)
        leg.networkVersion = "naturalearth-v5.1.2"
        #expect(leg.isMeasuredAlongTrack)
    }
}

@Suite("Detours")
struct TrackDetourTests {
    /// Out to 2°N, 1°E and back down to the equator at 2°E: two stretches of 248.6 km
    /// for a straight line of 222.4 km between the ends.
    static func network(_ kind: TrackKind) -> TrackNetwork {
        TrackNetwork(
            kind: kind,
            version: "test",
            nodes: [TrackFixture.at(0, 0), TrackFixture.at(2, 1), TrackFixture.at(0, 2)],
            edges: [
                TrackEdge(
                    a: 0,
                    b: 1,
                    lengthKm: 248.6,
                    points: [TrackFixture.at(0, 0), TrackFixture.at(2, 1)]
                ),
                TrackEdge(
                    a: 1,
                    b: 2,
                    lengthKm: 248.6,
                    points: [TrackFixture.at(2, 1), TrackFixture.at(0, 2)]
                ),
            ]
        )
    }

    @Test("A road or railway may wind; a ferry route that winds is not taken")
    func detours() throws {
        let from = TrackFixture.at(0, 0)
        let to = TrackFixture.at(0, 2)
        // 497.2 km is within 2.5 × 222.4 + 30 = 586 for a railway…
        let rail = try #require(Self.network(.rail).route(from: from, to: to))
        #expect(abs(rail.lengthKm - 497.2) < 0.01)
        // …but beyond 1.6 × 222.4 + 10 = 365.8 for a ferry.
        #expect(Self.network(.ferry).route(from: from, to: to) == nil)
    }
}

@Suite("Catalogue routes on a network")
struct TrackCatalogueTests {
    static func leg(storedKm: Double?) -> JourneyLeg {
        func place(_ latitude: Double, _ longitude: Double) -> PlaceReference {
            PlaceReference(
                id: .custom(UUID()),
                kind: .custom,
                name: "\(latitude), \(longitude)",
                coordinate: TrackFixture.at(latitude, longitude)
            )
        }
        // From node 4 (2°N, 1°E) to node 2 (0, 2°E): three degrees of track, 333.585 km.
        return JourneyLeg(
            mode: .rail,
            origin: place(2, 1),
            destination: place(0, 2),
            storedPathLengthKm: storedKm
        )
    }

    @Test("A catalogue route is drawn along the network only where the two agree")
    func catalogueAgreement() {
        // No length of its own: the network's way.
        #expect(TrackFixture.network.route(for: Self.leg(storedKm: nil)) != nil)
        // 350 km is within 15% of 333.585: the same route.
        #expect(TrackFixture.network.route(for: Self.leg(storedKm: 350)) != nil)
        // 450 km is not: the catalogue route went another way.
        #expect(TrackFixture.network.route(for: Self.leg(storedKm: 450)) == nil)
    }
}
