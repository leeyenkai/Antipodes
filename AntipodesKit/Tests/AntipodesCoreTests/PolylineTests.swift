import AntipodesCore
import Foundation
import Testing

@Suite("Polylines, lifts and trails")
struct PolylineTests {
    static func point(_ latitude: Double, _ longitude: Double) -> Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    /// A line running east along the equator, a point every tenth of a degree.
    static let line = (0 ... 10).map { point(0, Double($0) / 10) }

    @Test("A slice runs between the nearest points, in the direction travelled")
    func slice() throws {
        let east = try #require(Polyline.slice(
            Self.line,
            from: Self.point(0.001, 0.25),
            to: Self.point(0, 0.55)
        ))
        #expect(try abs(#require(east.first?.longitude) - 0.25) < 0.001)
        #expect(try abs(#require(east.last?.longitude) - 0.55) < 0.001)
        #expect(east.map(\.longitude) == east.map(\.longitude).sorted())

        let west = try #require(Polyline.slice(
            Self.line,
            from: Self.point(0, 0.55),
            to: Self.point(0, 0.25)
        ))
        #expect(west.map(\.longitude) == west.map(\.longitude).sorted(by: >))
    }

    @Test("A place far from the line gives no slice")
    func farAway() {
        #expect(Polyline.slice(Self.line, from: Self.point(1, 0.2), to: Self.point(0, 0.5)) == nil)
    }

    @Test("Among a route's parts, the one both places lie on is chosen")
    func among() throws {
        let branch = (0 ... 10).map { Self.point(Double($0) / 10, 2) }
        let path = try #require(Polyline.slice(
            among: [Self.line, branch],
            from: Self.point(0.2, 2),
            to: Self.point(0.7, 2)
        ))
        #expect(path.allSatisfy { abs($0.longitude - 2) < 0.001 })
    }

    @Test("Lifts that meet at a station make one ride up")
    func lifts() throws {
        let gondola = AerialLift(
            id: 1, kind: "gondola", name: "Plan de l'Aiguille", startName: "Chamonix",
            endName: "Plan",
            lengthKm: 2.6, points: [Self.point(45.9170, 6.8700), Self.point(45.8990, 6.8810)]
        )
        let cableCar = AerialLift(
            id: 2, kind: "cable_car", name: "Aiguille du Midi", startName: "Plan",
            endName: "Aiguille du Midi",
            lengthKm: 2.9, points: [Self.point(45.8992, 6.8812), Self.point(45.8790, 6.8870)]
        )
        let network = AerialLift.network([gondola, cableCar], version: "osm-test")
        #expect(network.nodes.count == 3)
        let ride = try #require(network.route(
            from: Self.point(45.9175, 6.8695),
            to: Self.point(45.8788, 6.8872)
        ))
        #expect(abs(ride.lengthKm - 5.5) < 0.2)
        #expect(gondola.kindName == "Gondola")
        #expect(TravelMode.cableAndMountain.trackKind == .lift)
        #expect(TrackKind.lift.isFromRoutePack)
    }

    @Test("Trails snap only to a nearby trailhead")
    func trailSnapping() {
        #expect(TrackKind.hiking.snapRadiusKm < TrackKind.rail.snapRadiusKm)
        #expect(TrackKind.bundled == [.rail, .road, .ferry])
        #expect(TrackKind.cycling.isTrail)
    }

    @Test("A region contains what lies inside its bounds")
    func regions() {
        let alps = TrailRegion(
            network: "hiking/alps",
            kind: .hiking,
            name: "The Alps",
            south: 43.6,
            west: 5,
            north: 48.4,
            east: 16.9
        )
        #expect(alps.contains(Self.point(46.0, 7.7)))
        #expect(!alps.contains(Self.point(51.5, -0.1)))
    }
}
