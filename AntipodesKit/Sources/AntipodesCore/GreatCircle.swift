import Foundation

/// Distances and paths on a spherical Earth.
///
/// This is the single implementation of distance in the app. Nothing else — no view,
/// no stat, no importer — computes a distance from coordinates (see AGENTS.md §7).
public enum GreatCircle {
    /// IUGG mean Earth radius, in kilometres.
    ///
    /// A sphere is accurate to roughly 0.3% against the WGS-84 ellipsoid, which is well
    /// inside what a travel log needs and matches how airlines quote great-circle
    /// distances.
    public static let earthRadiusKm = 6371.0088

    /// Circumference of the mean sphere, whose half is the furthest two places can be
    /// apart — an antipodal pair.
    public static let earthCircumferenceKm = 2 * Double.pi * earthRadiusKm

    /// Once round the Equator (WGS-84), the yardstick for "times round the Earth" and
    /// the "Round the world" badge, so the two agree on when the user has gone round.
    public static let equatorialCircumferenceKm = 40075.017

    /// Great-circle distance in kilometres, by the haversine formula.
    ///
    /// Haversine rather than the spherical law of cosines because it stays accurate for
    /// the short legs a city-transit ride produces, where `acos` loses precision.
    public static func distanceKm(from origin: Coordinate, to destination: Coordinate) -> Double {
        let deltaLatitude = destination.latitudeRadians - origin.latitudeRadians
        let deltaLongitude = destination.longitudeRadians - origin.longitudeRadians

        let haversine = pow(sin(deltaLatitude / 2), 2)
            + cos(origin.latitudeRadians) * cos(destination.latitudeRadians)
            * pow(sin(deltaLongitude / 2), 2)

        let centralAngle = 2 * asin(min(1, sqrt(haversine)))
        return earthRadiusKm * centralAngle
    }

    /// Angular separation in radians. Exposed because interpolation needs it and
    /// recomputing it from the distance loses precision at short range.
    public static func centralAngle(from origin: Coordinate, to destination: Coordinate) -> Double {
        distanceKm(from: origin, to: destination) / earthRadiusKm
    }

    /// Initial bearing in degrees clockwise from true north, in [0, 360).
    public static func initialBearingDegrees(
        from origin: Coordinate,
        to destination: Coordinate
    ) -> Double {
        let deltaLongitude = destination.longitudeRadians - origin.longitudeRadians
        let y = sin(deltaLongitude) * cos(destination.latitudeRadians)
        let x = cos(origin.latitudeRadians) * sin(destination.latitudeRadians)
            - sin(origin.latitudeRadians) * cos(destination.latitudeRadians) * cos(deltaLongitude)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    /// A point a given fraction along the great-circle path, by spherical linear
    /// interpolation.
    ///
    /// `fraction` is clamped to [0, 1]. Antipodal endpoints have no unique path, so the
    /// origin is returned rather than an arbitrary one.
    public static func interpolate(
        from origin: Coordinate,
        to destination: Coordinate,
        fraction: Double
    ) -> Coordinate {
        let t = min(1, max(0, fraction))
        if t == 0 {
            return origin
        }
        if t == 1 {
            return destination
        }

        let angle = centralAngle(from: origin, to: destination)
        guard angle > 1e-12, sin(angle) != 0 else { return origin }

        let a = sin((1 - t) * angle) / sin(angle)
        let b = sin(t * angle) / sin(angle)

        let x = a * cos(origin.latitudeRadians) * cos(origin.longitudeRadians)
            + b * cos(destination.latitudeRadians) * cos(destination.longitudeRadians)
        let y = a * cos(origin.latitudeRadians) * sin(origin.longitudeRadians)
            + b * cos(destination.latitudeRadians) * sin(destination.longitudeRadians)
        let z = a * sin(origin.latitudeRadians) + b * sin(destination.latitudeRadians)

        return Coordinate(
            latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
            longitude: atan2(y, x) * 180 / .pi
        )
    }

    /// The flight arc as drawn on the globe: the same curve the distance comes from
    /// (R-PATH-4), sampled into `segments` straight pieces.
    public static func arc(
        from origin: Coordinate,
        to destination: Coordinate,
        segments: Int = 64
    ) -> [Coordinate] {
        let count = max(1, segments)
        return (0 ... count).map { step in
            interpolate(from: origin, to: destination, fraction: Double(step) / Double(count))
        }
    }

    /// Total length of a stored path, summed leg by leg.
    ///
    /// Used for surface routes, where distance comes from real track or road geometry
    /// rather than a straight line (R-PATH-5).
    public static func pathLengthKm(_ path: [Coordinate]) -> Double {
        guard path.count > 1 else { return 0 }
        return zip(path, path.dropFirst()).reduce(0) { total, pair in
            total + distanceKm(from: pair.0, to: pair.1)
        }
    }
}
