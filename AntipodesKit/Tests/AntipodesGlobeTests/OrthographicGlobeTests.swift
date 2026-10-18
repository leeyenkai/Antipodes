import AntipodesCore
import AntipodesGlobe
import Foundation
import Testing

/// Expected values are the standard orthographic projection formulas worked out by
/// hand, which is the point: if the projection drifts, every pin and arc on the globe
/// drifts with it and nothing else in the app would notice.
///
///     x = cos φ · sin(λ − λ₀)
///     y = cos φ₀ · sin φ − sin φ₀ · cos φ · cos(λ − λ₀)
///     cos c = sin φ₀ · sin φ + cos φ₀ · cos φ · cos(λ − λ₀)
@Suite("Orthographic globe")
struct OrthographicGlobeTests {
    static let size = GlobeSize(width: 400, height: 400)
    /// 400 / 2 × 0.92 inset × zoom 1.
    static let radius = 184.0

    static func globe(
        latitude: Double = 0,
        longitude: Double = 0,
        zoom: Double = 1
    ) -> OrthographicGlobe {
        OrthographicGlobe(
            camera: GlobeCamera(
                centre: Coordinate(latitude: latitude, longitude: longitude),
                zoom: zoom
            ),
            size: size
        )
    }

    // MARK: - Projecting

    @Test("The camera's own centre lands in the middle of the view, facing us")
    func centreProjectsToMiddle() {
        let globe = Self.globe(latitude: 51.47, longitude: -0.4543)
        let projected = globe.project(Coordinate(latitude: 51.47, longitude: -0.4543))

        #expect(abs(projected.point.x - 200) < 0.001)
        #expect(abs(projected.point.y - 200) < 0.001)
        #expect(abs(projected.depth - 1) < 1e-12)
        #expect(projected.isVisible)
    }

    @Test("The point opposite the camera is on the far side and never drawn")
    func antipodeIsHidden() {
        let centre = Coordinate(latitude: 35.6762, longitude: 139.6503) // Tokyo
        let globe = Self.globe(latitude: centre.latitude, longitude: centre.longitude)
        let projected = globe.project(centre.antipode)

        #expect(abs(projected.depth + 1) < 1e-9)
        #expect(!projected.isVisible)
    }

    /// With the camera on the equator at 0°, a point at 30°E has x = sin 30° = 0.5.
    @Test("30 degrees east of centre is half a radius to the right")
    func eastwardOffset() {
        let projected = Self.globe().project(Coordinate(latitude: 0, longitude: 30))

        #expect(abs(projected.point.x - (200 + 0.5 * Self.radius)) < 0.001)
        #expect(abs(projected.point.y - 200) < 0.001)
        // cos c = cos 30° = 0.8660254
        #expect(abs(projected.depth - 0.866_025_403_784) < 1e-9)
    }

    /// y is positive northwards on the sphere and downwards on screen, so 30°N is half
    /// a radius *above* the middle.
    @Test("30 degrees north of centre is half a radius up the view")
    func northwardOffset() {
        let projected = Self.globe().project(Coordinate(latitude: 30, longitude: 0))

        #expect(abs(projected.point.x - 200) < 0.001)
        #expect(abs(projected.point.y - (200 - 0.5 * Self.radius)) < 0.001)
    }

    @Test("A quarter turn away sits exactly on the limb")
    func quarterTurnIsOnTheLimb() {
        let projected = Self.globe().project(Coordinate(latitude: 0, longitude: 90))

        #expect(abs(projected.point.x - (200 + Self.radius)) < 0.001)
        #expect(abs(projected.depth) < 1e-12)
        // Exactly on the limb counts as visible, so a clipped edge has somewhere to end.
        #expect(projected.isVisible)
    }

    @Test("Zoom multiplies the radius")
    func zoomScalesRadius() {
        #expect(abs(Self.globe(zoom: 1).radius - Self.radius) < 0.001)
        #expect(abs(Self.globe(zoom: 3).radius - Self.radius * 3) < 0.001)
    }

    // MARK: - Unprojecting

    @Test("Projecting then unprojecting a visible coordinate gives it back")
    func roundTrip() throws {
        let globe = Self.globe(latitude: 20, longitude: -30)
        let samples = [
            Coordinate(latitude: 20, longitude: -30),
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 51.47, longitude: -0.4543),
            Coordinate(latitude: -33.9399, longitude: -58.4),
            Coordinate(latitude: 60.1939, longitude: 11.1004),
        ]

        for coordinate in samples {
            let projected = globe.project(coordinate)
            try #require(projected.isVisible)
            let recovered = try #require(globe.coordinate(at: projected.point))
            #expect(abs(recovered.latitude - coordinate.latitude) < 1e-6)
            #expect(abs(recovered.longitude - coordinate.longitude) < 1e-6)
        }
    }

    @Test("A tap outside the globe's disc is not on the globe")
    func tapOutsideTheDisc() {
        let globe = Self.globe()
        #expect(globe.coordinate(at: GlobePoint(x: 200, y: 200)) != nil)
        #expect(globe.coordinate(at: GlobePoint(x: 395, y: 395)) == nil)
        #expect(globe.coordinate(at: GlobePoint(x: 200 + Self.radius + 1, y: 200)) == nil)
    }

    // MARK: - Clipping polylines

    @Test("A line that runs off the edge stops on the limb, not at the last vertex")
    func polylineClippedAtTheLimb() throws {
        let globe = Self.globe()
        // Walks east from the centre, past the limb at 90°E and on to the far side.
        let path = (0 ... 18).map { Coordinate(latitude: 0, longitude: Double($0) * 10) }
        let runs = globe.clippedPolyline(path)

        #expect(runs.count == 1)
        let run = try #require(runs.first)
        let last = try #require(run.last)
        // The run must end on the limb: exactly one radius from the centre.
        #expect(abs(last.distance(to: globe.centre) - Self.radius) < 0.5)
        // And every point of it is inside the disc.
        for point in run {
            #expect(point.distance(to: globe.centre) <= Self.radius + 0.5)
        }
    }

    @Test("A line that leaves view and comes back is drawn as two runs")
    func polylineSplitsIntoTwoRuns() {
        let globe = Self.globe()
        // Right round the equator starting at the centre of the view: visible out to
        // 90°E, hidden across the far side, then visible again from 90°W back to 0.
        let path = (0 ... 35).map { Coordinate(latitude: 0, longitude: Double($0) * 10) }
        let runs = globe.clippedPolyline(path)

        #expect(runs.count == 2)
        for run in runs {
            for point in run {
                #expect(point.distance(to: globe.centre) <= Self.radius + 0.5)
            }
        }
    }

    @Test("A line entirely on the far side is not drawn at all")
    func polylineFullyHidden() {
        let globe = Self.globe(latitude: 0, longitude: 0)
        let path = [
            Coordinate(latitude: 0, longitude: 150),
            Coordinate(latitude: 10, longitude: 170),
            Coordinate(latitude: -10, longitude: -170),
        ]
        #expect(globe.clippedPolyline(path).isEmpty)
    }

    // MARK: - Clipping rings

    @Test("A ring wholly in view keeps all of its points")
    func ringFullyVisible() {
        let globe = Self.globe()
        let ring = [
            Coordinate(latitude: 10, longitude: 10),
            Coordinate(latitude: 10, longitude: 20),
            Coordinate(latitude: 20, longitude: 20),
            Coordinate(latitude: 20, longitude: 10),
        ]
        #expect(globe.clippedRing(ring).count == 4)
    }

    @Test("A ring on the far side is dropped")
    func ringFullyHidden() {
        let globe = Self.globe()
        let ring = [
            Coordinate(latitude: 10, longitude: 160),
            Coordinate(latitude: 10, longitude: 170),
            Coordinate(latitude: 20, longitude: 170),
            Coordinate(latitude: 20, longitude: 160),
        ]
        #expect(globe.clippedRing(ring).isEmpty)
    }

    /// The part of the ring that went behind the globe has to be replaced by the arc of
    /// the limb it crossed. Joining the visible pieces with a straight line instead
    /// would cut a chord across the face of the globe, which is the characteristic bug
    /// in a hand-rolled orthographic fill.
    @Test("A ring straddling the limb is closed along the limb, inside the disc")
    func ringClosedAlongTheLimb() {
        let globe = Self.globe()
        // Straddles 90°E: half in view, half behind.
        let ring = [
            Coordinate(latitude: -10, longitude: 70),
            Coordinate(latitude: -10, longitude: 110),
            Coordinate(latitude: 10, longitude: 110),
            Coordinate(latitude: 10, longitude: 70),
        ]
        let clipped = globe.clippedRing(ring)

        #expect(clipped.count > 4, "the limb arc should have added points")
        for point in clipped {
            #expect(
                point.distance(to: globe.centre) <= Self.radius + 0.5,
                "no part of a clipped ring may fall outside the globe"
            )
        }
        // Several of the points should sit on the limb itself — that is the arc.
        let onLimb = clipped.filter { abs($0.distance(to: globe.centre) - Self.radius) < 0.5 }
        #expect(onLimb.count >= 3)
    }

    @Test("A ring round the pole keeps a sane, non-degenerate shape")
    func ringAroundThePole() {
        let globe = Self.globe(latitude: 60, longitude: 0)
        // A band near the north pole, which wraps all the way round in longitude.
        let ring = (0 ..< 36).map { Coordinate(latitude: 80, longitude: Double($0) * 10 - 180) }
        let clipped = globe.clippedRing(ring)

        #expect(!clipped.isEmpty)
        for point in clipped {
            #expect(point.distance(to: globe.centre) <= Self.radius + 0.5)
        }
    }

    // MARK: - Culling

    @Test("A box on the far side is skipped, one in view is not")
    func cullingRejectsTheFarSide() {
        let globe = Self.globe(latitude: 0, longitude: 0)

        let nearSide = BoundingBox(
            minimumLatitude: 40,
            minimumLongitude: -5,
            maximumLatitude: 55,
            maximumLongitude: 10
        )
        let farSide = BoundingBox(
            minimumLatitude: 30,
            minimumLongitude: 160,
            maximumLatitude: 45,
            maximumLongitude: 175
        )

        #expect(globe.mayBeVisible(box: nearSide))
        #expect(!globe.mayBeVisible(box: farSide))
    }

    /// Sampling a huge box can miss a visible middle, so the test passes it through
    /// rather than risking a hole in the map.
    @Test("A box too large to sample is never culled")
    func cullingKeepsHugeBoxes() {
        let globe = Self.globe(latitude: 0, longitude: 0)
        let russia = BoundingBox(
            minimumLatitude: 41,
            minimumLongitude: 19,
            maximumLatitude: 82,
            maximumLongitude: 180
        )
        #expect(russia.isTooLargeToSample)
        #expect(globe.mayBeVisible(box: russia))
    }

    @Test("A bounding box covers every coordinate it was built from")
    func boundingBoxCovers() throws {
        let box = try #require(
            BoundingBox(covering: [
                Coordinate(latitude: 10, longitude: -20),
                Coordinate(latitude: -5, longitude: 30),
                Coordinate(latitude: 25, longitude: 5),
            ])
        )
        #expect(box.minimumLatitude == -5)
        #expect(box.maximumLatitude == 25)
        #expect(box.minimumLongitude == -20)
        #expect(box.maximumLongitude == 30)
        #expect(BoundingBox(covering: []) == nil)
    }
}

@Suite("Globe camera")
struct GlobeCameraTests {
    static let size = GlobeSize(width: 400, height: 400)

    @Test("Zoom is clamped to a usable range")
    func zoomClamped() {
        #expect(GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0), zoom: 0.1).zoom == 1)
        #expect(GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0), zoom: 1000).zoom == 24)
    }

    @Test("The camera stops short of the poles so the globe cannot flip over")
    func latitudeClamped() {
        let north = GlobeCamera(centre: Coordinate(latitude: 89.9, longitude: 0))
        let south = GlobeCamera(centre: Coordinate(latitude: -89.9, longitude: 0))
        #expect(north.centre.latitude == GlobeCamera.latitudeLimit)
        #expect(south.centre.latitude == -GlobeCamera.latitudeLimit)
    }

    /// Dragging one radius' worth of points turns the globe by one radian, so the
    /// surface keeps up with the finger.
    @Test("A drag of one radius turns the globe by a radian")
    func dragTurnsByARadian() {
        let camera = GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0), zoom: 1)
        let radius = camera.radius(fitting: Self.size)
        let dragged = camera.dragged(dx: radius, dy: 0, in: Self.size)

        // Dragging right spins the globe westwards, bringing eastern longitudes into view.
        #expect(abs(dragged.centre.longitude + 180 / .pi) < 1e-9)
    }

    @Test("Zooming in makes the same drag turn the globe less")
    func dragScalesWithZoom() {
        let near = GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0), zoom: 4)
        let far = GlobeCamera(centre: Coordinate(latitude: 0, longitude: 0), zoom: 1)

        let nearTurn = abs(near.dragged(dx: 50, dy: 0, in: Self.size).centre.longitude)
        let farTurn = abs(far.dragged(dx: 50, dy: 0, in: Self.size).centre.longitude)
        #expect(abs(farTurn - nearTurn * 4) < 1e-9)
    }

    /// Flying from Tokyo to Los Angeles should cross the Pacific, not spin backwards
    /// across Europe and the Atlantic.
    @Test("Interpolating longitude takes the short way round the antimeridian")
    func interpolationTakesTheShortWay() {
        let tokyo = GlobeCamera(centre: Coordinate(latitude: 35.7, longitude: 139.7))
        let losAngeles = GlobeCamera(centre: Coordinate(latitude: 34.0, longitude: -118.2))
        let halfway = tokyo.interpolated(to: losAngeles, fraction: 0.5)

        // Eastwards is 102.1° of longitude; westwards would be 257.9°. Halfway along
        // the short way is 139.7 + 51.05 = 190.75°, which normalises to -169.25°:
        // out in the Pacific, just past the antimeridian.
        #expect(abs(halfway.centre.longitude - -169.25) < 1e-9)
    }

    @Test("Interpolation ends exactly where it was asked to")
    func interpolationEndpoints() {
        let from = GlobeCamera(centre: Coordinate(latitude: 10, longitude: 20), zoom: 1)
        let to = GlobeCamera(centre: Coordinate(latitude: -30, longitude: 60), zoom: 4)

        #expect(from.interpolated(to: to, fraction: 0) == from)
        let end = from.interpolated(to: to, fraction: 1)
        #expect(abs(end.centre.latitude - -30) < 1e-9)
        #expect(abs(end.centre.longitude - 60) < 1e-9)
        #expect(abs(end.zoom - 4) < 1e-9)
    }
}
