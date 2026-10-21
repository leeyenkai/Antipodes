import AntipodesCore
import AntipodesStats
import Foundation
import Testing

/// A system (100) of two lines. Line 10 runs 1–2–3–4 with a branch 3–5, a Y; line 20
/// runs 4–6. Five segments in all: 1–2, 2–3, 3–4, 3–5 and 4–6.
enum TransitFixture {
    static let system = TransitSystemInfo(
        id: 100,
        name: "Test Metro",
        kind: "metro",
        cityName: "Testville",
        countryCode: "NO",
        networkVersion: "wikidata-2026-10-21"
    )
    static let network = TransitNetwork(
        systems: [100: system],
        lines: [
            10: TransitLineInfo(
                id: 10,
                systemID: 100,
                name: "Red",
                shortName: "R",
                colour: "FF0000"
            ),
            20: TransitLineInfo(id: 20, systemID: 100, name: "Blue", shortName: nil, colour: nil),
        ],
        stops: Dictionary(uniqueKeysWithValues: (1 ... 6).map { id in
            (
                Int64(id),
                TransitStop(
                    id: Int64(id),
                    name: "S\(id)",
                    // One hundredth of a degree of latitude apart: 1.112 km each.
                    coordinate: Coordinate(latitude: 60 + Double(id) / 100, longitude: 10)
                )
            )
        }),
        segments: [
            TransitSegment(lineID: 10, between: 1, and: 2),
            TransitSegment(lineID: 10, between: 3, and: 2),
            TransitSegment(lineID: 10, between: 3, and: 4),
            TransitSegment(lineID: 10, between: 5, and: 3),
            TransitSegment(lineID: 20, between: 4, and: 6),
        ]
    )

    static func station(_ id: Int64) -> PlaceReference {
        PlaceReference(id: .database(.station, id), kind: .station, name: "S\(id)")
    }

    static func ride(_ line: Int64?, _ from: Int64, _ to: Int64) -> JourneyLeg {
        JourneyLeg(
            mode: .cityTransit,
            origin: station(from),
            destination: station(to),
            transitLineID: line
        )
    }
}

@Suite("City transit")
struct TransitStatisticsTests {
    @Test("A ride takes the fewest segments along its line, either way, branches included")
    func routing() {
        let network = TransitFixture.network
        #expect(network.route(onLine: 10, from: 1, to: 4) == [1, 2, 3, 4])
        #expect(network.route(onLine: 10, from: 5, to: 1) == [5, 3, 2, 1])
        #expect(network.route(onLine: 10, from: 2, to: 2) == [2])
        // Stop 6 is on the Blue line, not the Red.
        #expect(network.route(onLine: 10, from: 1, to: 6) == nil)
    }

    /// From the lowest-numbered end (1): along the trunk to 4, then the branch to 5.
    @Test("A line's stops are listed in riding order from one end, branches after")
    func ordering() {
        #expect(TransitFixture.network.orderedStops(ofLine: 10) == [1, 2, 3, 4, 5])
    }

    /// Three hops of 0.01° of latitude: 3 × 1.112 km ≈ 3.336 km.
    @Test("A ride's length runs stop to stop")
    func length() throws {
        let length = try #require(TransitFixture.network.lengthKm(of: [1, 2, 3, 4]))
        #expect(abs(length - 3.336) < 0.01)
    }

    /// Ride 1→4 on Red covers 1–2, 2–3, 3–4. Ride 4→3 on Red covers 3–4 again: a ride,
    /// not coverage. A ride logged between two places has no line; a ride from 1 to 6
    /// "on Red" cannot be routed. Three segments of five: 60 %. Stop 2 is the only one
    /// passed without getting on or off.
    @Test("Coverage counts unique segments; stations count boarded, alighted and passed")
    func coverage() throws {
        let log = TravelLog(journeys: [
            Journey(legs: [TransitFixture.ride(10, 1, 4)]),
            Journey(legs: [TransitFixture.ride(10, 4, 3)]),
            Journey(legs: [TransitFixture.ride(nil, 1, 4)]),
            Journey(legs: [TransitFixture.ride(10, 1, 6)]),
        ])
        let stats = TransitStatistics.compute(for: log, network: TransitFixture.network)
        #expect(stats.rides == 4)
        let system = try #require(stats.systems.first)
        #expect(system.segmentsRidden == 3)
        #expect(system.segmentsTotal == 5)
        #expect(abs(system.fraction - 0.6) < 1e-9)
        #expect(system.linesRidden == 1)
        #expect(system.lines.first?.line.name == "Red")
        #expect(stats.boarded == [1, 4])
        #expect(stats.alighted == [3, 4, 6])
        #expect(stats.passedThrough == [2])
        #expect(stats.stationsVisited == [1, 2, 3, 4, 6])
        #expect(stats.input.used == 2)
        #expect(stats.input.exclusions[.noTransitLine] == 1)
        #expect(stats.input.exclusions[.transitRouteUnknown] == 1)
    }
}
