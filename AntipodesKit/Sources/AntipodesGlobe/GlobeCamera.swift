import AntipodesCore
import Foundation

/// Where the globe is looking from, and how close.
///
/// The whole camera is two numbers and a coordinate, which is what makes the replay and
/// the "fly to this visit" animations straightforward: they interpolate a camera, not a
/// renderer state.
public struct GlobeCamera: Hashable, Sendable {
    /// The coordinate at the centre of the view.
    public let centre: Coordinate
    /// 1 shows the whole globe; larger numbers zoom in.
    public let zoom: Double

    /// Beyond this the far side starts to matter and the poles become hard to steer
    /// past, so the camera stops short of them.
    public static let latitudeLimit = 85.0
    public static let minimumZoom = 1.0
    public static let maximumZoom = 24.0

    /// The globe leaves a margin so pins near the limb are not clipped by the view edge.
    static let fitInset = 0.92

    public static let `default` = GlobeCamera(
        centre: Coordinate(latitude: 25, longitude: 10),
        zoom: 1
    )

    public init(centre: Coordinate, zoom: Double = 1) {
        self.centre = Coordinate(
            latitude: min(
                GlobeCamera.latitudeLimit,
                max(-GlobeCamera.latitudeLimit, centre.latitude)
            ),
            longitude: centre.longitude
        )
        self.zoom = min(GlobeCamera.maximumZoom, max(GlobeCamera.minimumZoom, zoom))
    }

    public func radius(fitting size: GlobeSize) -> Double {
        size.minimumEdge / 2 * GlobeCamera.fitInset * zoom
    }

    /// The camera after a drag of `dx`, `dy` points.
    ///
    /// A drag turns the globe under the finger: the angle swept is the distance dragged
    /// over the radius, so the same gesture turns the globe less when it is zoomed in,
    /// which is what makes it feel like a ball rather than a slider.
    public func dragged(dx: Double, dy: Double, in size: GlobeSize) -> GlobeCamera {
        let radius = radius(fitting: size)
        guard radius > 0 else { return self }
        let degreesPerPoint = 180 / .pi / radius
        return GlobeCamera(
            centre: Coordinate(
                latitude: centre.latitude + dy * degreesPerPoint,
                longitude: centre.longitude - dx * degreesPerPoint
            ),
            zoom: zoom
        )
    }

    public func zoomed(by factor: Double) -> GlobeCamera {
        GlobeCamera(centre: centre, zoom: zoom * factor)
    }

    public func looking(at coordinate: Coordinate) -> GlobeCamera {
        GlobeCamera(centre: coordinate, zoom: zoom)
    }

    /// A camera part-way between two, for animating a move to a place.
    ///
    /// Longitude takes the short way round, so flying from Tokyo to Los Angeles crosses
    /// the Pacific rather than spinning back across Europe.
    public func interpolated(to other: GlobeCamera, fraction: Double) -> GlobeCamera {
        let t = min(1, max(0, fraction))
        var deltaLongitude = other.centre.longitude - centre.longitude
        if deltaLongitude > 180 {
            deltaLongitude -= 360
        }
        if deltaLongitude < -180 {
            deltaLongitude += 360
        }
        return GlobeCamera(
            centre: Coordinate(
                latitude: centre.latitude + (other.centre.latitude - centre.latitude) * t,
                longitude: centre.longitude + deltaLongitude * t
            ),
            zoom: zoom + (other.zoom - zoom) * t
        )
    }
}

/// A latitude/longitude box, used to skip geometry that cannot be on screen.
public struct BoundingBox: Hashable, Sendable {
    public let minimumLatitude: Double
    public let minimumLongitude: Double
    public let maximumLatitude: Double
    public let maximumLongitude: Double

    public init(
        minimumLatitude: Double,
        minimumLongitude: Double,
        maximumLatitude: Double,
        maximumLongitude: Double
    ) {
        self.minimumLatitude = minimumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLatitude = maximumLatitude
        self.maximumLongitude = maximumLongitude
    }

    public init?(covering coordinates: [Coordinate]) {
        guard let first = coordinates.first else { return nil }
        var box = BoundingBox(
            minimumLatitude: first.latitude,
            minimumLongitude: first.longitude,
            maximumLatitude: first.latitude,
            maximumLongitude: first.longitude
        )
        for coordinate in coordinates.dropFirst() {
            box = BoundingBox(
                minimumLatitude: min(box.minimumLatitude, coordinate.latitude),
                minimumLongitude: min(box.minimumLongitude, coordinate.longitude),
                maximumLatitude: max(box.maximumLatitude, coordinate.latitude),
                maximumLongitude: max(box.maximumLongitude, coordinate.longitude)
            )
        }
        self = box
    }

    public var latitudeSpan: Double {
        maximumLatitude - minimumLatitude
    }

    public var longitudeSpan: Double {
        maximumLongitude - minimumLongitude
    }

    /// A box this wide is not worth testing: sampling it could miss a visible middle,
    /// so the culling test passes it through instead.
    static let samplingLimit = 60.0

    /// Corners, edge midpoints and centre — the points the culling test checks.
    public var samplePoints: [Coordinate] {
        let latitudes = [minimumLatitude, (minimumLatitude + maximumLatitude) / 2, maximumLatitude]
        let longitudes = [
            minimumLongitude,
            (minimumLongitude + maximumLongitude) / 2,
            maximumLongitude,
        ]
        return latitudes.flatMap { latitude in
            longitudes.map { Coordinate(latitude: latitude, longitude: $0) }
        }
    }

    public var isTooLargeToSample: Bool {
        latitudeSpan > BoundingBox.samplingLimit || longitudeSpan > BoundingBox.samplingLimit
    }
}

public extension GlobeCamera {
    /// A camera that shows every coordinate: centred on their mean direction, and zoomed
    /// in as far as keeps the furthest one inside 80% of the disc.
    ///
    /// On an orthographic globe a point θ from the centre lands r·sin θ from the middle
    /// of the disc, so the furthest point fits at a zoom of 0.8 / sin θ. Anything more
    /// than 60° out needs the whole hemisphere, and a single point gets a city-scale
    /// view rather than an infinite zoom.
    static func framing(_ coordinates: [Coordinate], maximumZoom: Double = 10) -> GlobeCamera? {
        guard !coordinates.isEmpty else { return nil }
        var sum = Vector3(x: 0, y: 0, z: 0)
        for coordinate in coordinates {
            sum = sum.adding(Vector3.onUnitSphere(coordinate))
        }
        let length = (sum.x * sum.x + sum.y * sum.y + sum.z * sum.z).squareRoot()
        guard length > 1e-6 else { return GlobeCamera(centre: coordinates[0], zoom: 1) }
        let centre = sum.coordinate
        let spread = coordinates
            .map { GreatCircle.centralAngle(from: centre, to: $0) }
            .max() ?? 0
        guard spread < .pi / 3 else { return GlobeCamera(centre: centre, zoom: 1) }
        let zoom = spread < 1e-4 ? maximumZoom : 0.8 / sin(spread)
        return GlobeCamera(centre: centre, zoom: min(maximumZoom, max(1, zoom)))
    }
}
