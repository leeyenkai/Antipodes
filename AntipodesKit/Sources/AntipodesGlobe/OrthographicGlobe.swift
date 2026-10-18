import AntipodesCore
import Foundation

/// A point in the view's coordinate space, in points, y increasing downwards.
///
/// Deliberately not `CGPoint`: this module is pure maths and is tested without any
/// graphics framework. The view converts at the boundary.
public struct GlobePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: GlobePoint) -> Double {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A coordinate projected onto the view.
public struct ProjectedPoint: Hashable, Sendable {
    public let point: GlobePoint
    /// Cosine of the angle from the centre of the view to the coordinate. Positive on
    /// the near hemisphere, negative on the far side, zero exactly on the limb.
    public let depth: Double

    public var isVisible: Bool {
        depth >= 0
    }
}

/// An orthographic projection of the sphere: what a globe looks like from far away.
///
/// This is the whole renderer's geometry. The globe draws vector borders, arcs and pins
/// through it rather than fetching map imagery, which is what lets the signature screen
/// work in airplane mode (decision D-5, R-GLOBE-1).
///
/// The projection is the standard orthographic one, carried out in Cartesian space so
/// that clipping can interpolate along a real great circle rather than in screen space.
public struct OrthographicGlobe: Sendable {
    public let camera: GlobeCamera
    /// Centre of the globe in view coordinates.
    public let centre: GlobePoint
    /// Radius of the globe in points.
    public let radius: Double

    private let axis: Vector3
    private let east: Vector3
    private let north: Vector3

    public init(camera: GlobeCamera, size: GlobeSize) {
        self.camera = camera
        centre = GlobePoint(x: size.width / 2, y: size.height / 2)
        radius = camera.radius(fitting: size)

        let latitude = camera.centre.latitudeRadians
        let longitude = camera.centre.longitudeRadians
        axis = Vector3.onUnitSphere(latitude: latitude, longitude: longitude)
        // The view's right and up directions on the sphere at the camera centre.
        east = Vector3(x: -sin(longitude), y: cos(longitude), z: 0)
        north = Vector3(
            x: -sin(latitude) * cos(longitude),
            y: -sin(latitude) * sin(longitude),
            z: cos(latitude)
        )
    }

    // MARK: - Projecting

    public func project(_ coordinate: Coordinate) -> ProjectedPoint {
        project(Vector3.onUnitSphere(coordinate))
    }

    private func project(_ point: Vector3) -> ProjectedPoint {
        let unitX = point.dot(east)
        let unitY = point.dot(north)
        return ProjectedPoint(
            point: GlobePoint(
                x: centre.x + unitX * radius,
                y: centre.y - unitY * radius
            ),
            depth: point.dot(axis)
        )
    }

    /// The coordinate under a point in the view, or `nil` outside the globe's disc.
    ///
    /// Used for tapping the globe and for working out what a drag grabbed.
    public func coordinate(at point: GlobePoint) -> Coordinate? {
        guard radius > 0 else { return nil }
        let unitX = (point.x - centre.x) / radius
        let unitY = (centre.y - point.y) / radius
        let squaredRadius = unitX * unitX + unitY * unitY
        guard squaredRadius <= 1 else { return nil }

        // Reconstruct the sphere point: the component along the view axis is whatever
        // is left over once the in-plane components are accounted for.
        let depth = (1 - squaredRadius).squareRoot()
        let position = axis.scaled(by: depth)
            .adding(east.scaled(by: unitX))
            .adding(north.scaled(by: unitY))
        return position.coordinate
    }

    // MARK: - Clipping

    /// A polyline clipped to the near hemisphere, split wherever it goes behind the
    /// globe and cut exactly on the limb.
    ///
    /// A flight arc from Tokyo to London crosses the limb at most of the globe's
    /// orientations, and a renderer that simply dropped the hidden vertices would leave
    /// the line stopping short of the edge.
    public func clippedPolyline(_ coordinates: [Coordinate]) -> [[GlobePoint]] {
        let points = coordinates.map(Vector3.onUnitSphere)
        guard points.count > 1 else {
            return points.first.map { project($0).isVisible ? [[project($0).point]] : [] } ?? []
        }

        var runs: [[GlobePoint]] = []
        var current: [GlobePoint] = []

        for index in points.indices {
            let projected = project(points[index])
            if projected.isVisible {
                if current.isEmpty, index > 0 {
                    // Entering view: start at the limb, not at the first visible vertex.
                    current.append(limbCrossing(from: points[index - 1], to: points[index]))
                }
                current.append(projected.point)
            } else if !current.isEmpty {
                current.append(limbCrossing(from: points[index - 1], to: points[index]))
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs.filter { $0.count > 1 }
    }

    /// A closed ring clipped to the near hemisphere and closed along the limb, ready to
    /// fill.
    ///
    /// Country polygons routinely straddle the edge of the visible hemisphere. Joining
    /// the visible pieces with a straight line would cut a chord across the globe, so
    /// the hidden parts are replaced by the arc of the limb they crossed.
    public func clippedRing(_ coordinates: [Coordinate]) -> [GlobePoint] {
        let points = coordinates.map(Vector3.onUnitSphere)
        guard points.count > 2 else { return [] }

        let visibility = points.map { project($0).depth >= 0 }
        if visibility.allSatisfy(\.self) {
            return points.map { project($0).point }
        }
        guard visibility.contains(true) else { return [] }

        // Walk the ring from a vertex that has just come into view, so the runs come out
        // in order and each is followed by the hidden stretch it has to be joined
        // across.
        guard let start = visibility.indices.first(where: { index in
            visibility[index] && !visibility[(index + points.count - 1) % points.count]
        }) else { return [] }

        var result: [GlobePoint] = []
        var index = 0
        let count = points.count

        while index < count {
            let current = (start + index) % count
            guard visibility[current] else { index += 1; continue }

            let previous = (current + count - 1) % count
            result.append(limbCrossing(from: points[previous], to: points[current]))

            // The visible run.
            var length = 0
            while length < count, visibility[(current + length) % count] {
                result.append(project(points[(current + length) % count]).point)
                length += 1
            }

            let lastVisible = (current + length - 1) % count
            let firstHidden = (current + length) % count
            let exit = limbCrossing(from: points[lastVisible], to: points[firstHidden])
            result.append(exit)

            // The hidden run, which becomes an arc of the limb.
            var hiddenLength = 0
            while hiddenLength < count, !visibility[(firstHidden + hiddenLength) % count] {
                hiddenLength += 1
            }
            let reentry = (firstHidden + hiddenLength) % count
            let entry = limbCrossing(
                from: points[(reentry + count - 1) % count],
                to: points[reentry]
            )
            let midHidden = points[(firstHidden + hiddenLength / 2) % count]
            result.append(contentsOf: limbArc(from: exit, to: entry, passing: midHidden))

            index += length + hiddenLength
        }
        return result
    }

    /// Where the great circle between two points crosses the limb.
    ///
    /// Found by bisection along the same interpolation the arc itself is drawn with, so
    /// the cut lands on the curve rather than near it.
    private func limbCrossing(from origin: Vector3, to destination: Vector3) -> GlobePoint {
        var low = 0.0
        var high = 1.0
        let originIsVisible = origin.dot(axis) >= 0

        for _ in 0 ..< 32 {
            let middle = (low + high) / 2
            let point = origin.interpolated(to: destination, fraction: middle)
            if (point.dot(axis) >= 0) == originIsVisible {
                low = middle
            } else {
                high = middle
            }
        }

        // Project the midpoint of the bracket and push it onto the limb exactly, so
        // adjacent clipped rings meet without a seam.
        let crossing = origin.interpolated(to: destination, fraction: (low + high) / 2)
        let unitX = crossing.dot(east)
        let unitY = crossing.dot(north)
        let length = (unitX * unitX + unitY * unitY).squareRoot()
        guard length > 0 else { return GlobePoint(x: centre.x + radius, y: centre.y) }
        return GlobePoint(
            x: centre.x + unitX / length * radius,
            y: centre.y - unitY / length * radius
        )
    }

    /// The arc of the limb between two points on it, going the way round that the
    /// hidden part of the ring went.
    ///
    /// `passing` is a point from the hidden stretch. Its direction from the centre says
    /// which of the two possible arcs is the right one — without it, a country wrapped
    /// round the far side would be filled inside out.
    private func limbArc(
        from start: GlobePoint,
        to end: GlobePoint,
        passing: Vector3
    ) -> [GlobePoint] {
        let startAngle = angle(of: start)
        let endAngle = angle(of: end)
        let hiddenAngle = atan2(passing.dot(north), passing.dot(east))

        let anticlockwiseSweep = normalisedAngle(endAngle - startAngle)
        let hiddenOffset = normalisedAngle(hiddenAngle - startAngle)
        let goesAnticlockwise = hiddenOffset <= anticlockwiseSweep
        let sweep = goesAnticlockwise ? anticlockwiseSweep : anticlockwiseSweep - 2 * .pi

        // One segment per couple of degrees: enough that the edge reads as a circle.
        let steps = max(1, Int(abs(sweep) / (.pi / 90)))
        return (1 ... steps).map { step in
            let angle = startAngle + sweep * Double(step) / Double(steps)
            return GlobePoint(
                x: centre.x + cos(angle) * radius,
                y: centre.y - sin(angle) * radius
            )
        }
    }

    private func angle(of point: GlobePoint) -> Double {
        atan2(centre.y - point.y, point.x - centre.x)
    }

    /// An angle moved into [0, 2π).
    private func normalisedAngle(_ angle: Double) -> Double {
        let remainder = angle.truncatingRemainder(dividingBy: 2 * .pi)
        return remainder < 0 ? remainder + 2 * .pi : remainder
    }

    // MARK: - Culling

    /// Whether any part of a latitude/longitude box could be on the near hemisphere.
    ///
    /// Cheap rejection before a country's rings are projected point by point: at a
    /// typical orientation it discards more than half of the world.
    public func mayBeVisible(box: BoundingBox) -> Bool {
        // A box big enough that its middle could be visible while every sample is not
        // is passed through rather than sampled: skipping real geometry would be a
        // visible hole, and skipping the test only costs a projection.
        guard !box.isTooLargeToSample else { return true }
        // The margin covers geometry just over the limb whose clipped edge still shows.
        for coordinate in box.samplePoints where project(coordinate).depth >= -0.05 {
            return true
        }
        return false
    }
}

/// The size of the view the globe is drawn into, in points.
public struct GlobeSize: Hashable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var minimumEdge: Double {
        min(width, height)
    }
}

// MARK: - Vector maths

/// A point in Cartesian space on the unit sphere.
///
/// Internal on purpose: nothing outside this module needs to think in vectors, and
/// keeping it private stops a second coordinate convention leaking into the app.
struct Vector3: Sendable {
    let x: Double
    let y: Double
    let z: Double

    static func onUnitSphere(latitude: Double, longitude: Double) -> Vector3 {
        Vector3(
            x: cos(latitude) * cos(longitude),
            y: cos(latitude) * sin(longitude),
            z: sin(latitude)
        )
    }

    static func onUnitSphere(_ coordinate: Coordinate) -> Vector3 {
        onUnitSphere(latitude: coordinate.latitudeRadians, longitude: coordinate.longitudeRadians)
    }

    func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    func scaled(by factor: Double) -> Vector3 {
        Vector3(x: x * factor, y: y * factor, z: z * factor)
    }

    func adding(_ other: Vector3) -> Vector3 {
        Vector3(x: x + other.x, y: y + other.y, z: z + other.z)
    }

    var normalised: Vector3 {
        let length = (x * x + y * y + z * z).squareRoot()
        return length > 0 ? scaled(by: 1 / length) : self
    }

    var coordinate: Coordinate {
        let unit = normalised
        return Coordinate(
            latitude: asin(min(1, max(-1, unit.z))) * 180 / .pi,
            longitude: atan2(unit.y, unit.x) * 180 / .pi
        )
    }

    /// Straight-line interpolation followed by a push back onto the sphere.
    ///
    /// For finding where a curve crosses the limb this is the same curve as spherical
    /// interpolation — the normalised chord traces the great circle — and it stays well
    /// behaved for the tiny steps bisection ends up taking.
    func interpolated(to other: Vector3, fraction: Double) -> Vector3 {
        Vector3(
            x: x + (other.x - x) * fraction,
            y: y + (other.y - y) * fraction,
            z: z + (other.z - z) * fraction
        ).normalised
    }
}
