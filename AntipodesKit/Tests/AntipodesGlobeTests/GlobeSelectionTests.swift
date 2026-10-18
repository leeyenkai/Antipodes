import AntipodesCore
import AntipodesGlobe
import Foundation
import Testing

/// Tapping the globe, and working out where to point it.
///
/// Split from `GlobeSceneTests` only to keep each file a readable length; the
/// fixtures are shared.
@Suite("Globe selection")
struct GlobeSelectionTests {
    @Test("Tapping a pin selects it")
    func tapSelectsPin() {
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(visits: [Visit(place: GlobeFixtures.oslo)]),
            rules: .default
        )
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: GlobeFixtures.osloCoordinate, zoom: 1),
            size: GlobeSize(width: 400, height: 400)
        )

        let selection = scene.selection(at: GlobePoint(x: 200, y: 200), globe: globe)
        guard case let .pin(pin) = selection else {
            Issue.record("expected a pin, got \(String(describing: selection))")
            return
        }
        #expect(pin.place.name == "Oslo")
    }

    @Test("Tapping empty ocean selects nothing")
    func tapSelectsNothing() {
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(visits: [Visit(place: GlobeFixtures.oslo)]),
            rules: .default
        )
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: GlobeFixtures.osloCoordinate, zoom: 1),
            size: GlobeSize(width: 400, height: 400)
        )

        #expect(scene.selection(at: GlobePoint(x: 60, y: 340), globe: globe) == nil)
    }

    /// A pin sitting on an arc is the more specific thing to open, so it wins.
    @Test("A pin beats an arc running underneath it")
    func pinBeatsArc() {
        let leg = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.tokyo
        )
        let log = TravelLog(
            visits: [Visit(place: GlobeFixtures.oslo)],
            journeys: [Journey(legs: [leg])]
        )
        let scene = GlobeSceneBuilder.build(log: log, rules: .default)
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: GlobeFixtures.osloCoordinate, zoom: 1),
            size: GlobeSize(width: 400, height: 400)
        )

        let selection = scene.selection(at: GlobePoint(x: 200, y: 200), globe: globe)
        guard case .pin = selection else {
            Issue.record("expected the pin to win, got \(String(describing: selection))")
            return
        }
    }

    @Test("Tapping along an arc away from any pin selects the arc")
    func tapSelectsArc() throws {
        let leg = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome
        )
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(journeys: [Journey(legs: [leg])]),
            rules: .default
        )
        let globe = OrthographicGlobe(
            camera: GlobeCamera(
                centre: Coordinate(latitude: 50, longitude: 11),
                zoom: 1
            ),
            size: GlobeSize(width: 400, height: 400)
        )

        // Halfway along the drawn path, which is where no pin is.
        let arc = try #require(scene.arcs.first)
        let midpoint = globe.project(arc.path[arc.path.count / 2])
        try #require(midpoint.isVisible)

        let selection = scene.selection(at: midpoint.point, globe: globe)
        guard case let .arc(selected) = selection else {
            Issue.record("expected an arc, got \(String(describing: selection))")
            return
        }
        #expect(selected.id == leg.id)
    }

    @Test("A pin on the far side of the globe cannot be tapped")
    func farSidePinIsNotSelectable() {
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(visits: [Visit(place: GlobeFixtures.tokyo)]),
            rules: .default
        )
        // Looking at Tokyo's antipode, so Tokyo is behind the globe.
        let globe = OrthographicGlobe(
            camera: GlobeCamera(centre: GlobeFixtures.tokyoCoordinate.antipode, zoom: 1),
            size: GlobeSize(width: 400, height: 400)
        )

        #expect(scene.selection(at: GlobePoint(x: 200, y: 200), globe: globe) == nil)
    }
}

@Suite("Globe framing")
struct GlobeFramingTests {
    @Test("An empty scene has nothing to point the camera at")
    func emptySceneHasNoFocus() {
        #expect(GlobeScene.empty.focusCoordinate == nil)
    }

    @Test("A single place is what the camera looks at")
    func singlePlace() throws {
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(visits: [Visit(place: GlobeFixtures.oslo)]),
            rules: .default
        )
        let focus = try #require(scene.focusCoordinate)

        #expect(abs(focus.latitude - GlobeFixtures.osloCoordinate.latitude) < 1e-6)
        #expect(abs(focus.longitude - GlobeFixtures.osloCoordinate.longitude) < 1e-6)
    }

    /// Averaging longitude numerically would put the midpoint of 139°E and 118°W in
    /// the Sahara. Averaging directions puts it in the Pacific, where it belongs.
    @Test("Two places either side of the antimeridian focus on the Pacific, not Africa")
    func antimeridianFocus() throws {
        let tokyo = GlobeFixtures.city(
            "Tokyo", "JP", Coordinate(latitude: 0, longitude: 170), id: 1
        )
        let hawaii = GlobeFixtures.city(
            "Honolulu", "US", Coordinate(latitude: 0, longitude: -170), id: 2
        )
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(visits: [Visit(place: tokyo), Visit(place: hawaii)]),
            rules: .default
        )
        let focus = try #require(scene.focusCoordinate)

        #expect(abs(abs(focus.longitude) - 180) < 1e-6)
        #expect(abs(focus.latitude) < 1e-6)
    }

    /// Travel spread evenly over the whole globe has no one side to show, and the mean
    /// direction collapses to the centre of the Earth. Reported as "no answer" rather
    /// than an arbitrary one.
    @Test("Perfectly opposite places have no single side to look at")
    func antipodalPlacesHaveNoFocus() {
        let here = GlobeFixtures.city("Here", "AA", Coordinate(latitude: 0, longitude: 0), id: 1)
        let there = GlobeFixtures.city(
            "There",
            "BB",
            Coordinate(latitude: 0, longitude: 180),
            id: 2
        )
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(visits: [Visit(place: here), Visit(place: there)]),
            rules: .default
        )

        #expect(scene.focusCoordinate == nil)
    }
}
