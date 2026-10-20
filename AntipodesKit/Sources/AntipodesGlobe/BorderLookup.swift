import AntipodesCore
import Foundation

/// Which country a point is in, from the bundled outlines alone (R-LOG-5, §12
/// "Offline geocoding").
///
/// A dropped pin has to count towards coverage, so it needs a country, and asking a
/// geocoding service would send the user's own location off the device (R-PRIV-3).
/// Point-in-polygon against the same Natural Earth outlines the globe shades means the
/// pin's country and the shading beneath it can never disagree.
public extension CountryBorders {
    /// The ISO code of the country containing `coordinate`, or `nil` at sea, in
    /// Antarctica's unclaimed interior, or on land Natural Earth gives no code.
    ///
    /// Even-odd ray casting over each ring in plain latitude and longitude. That is
    /// exact for the test the outlines were drawn for — they are themselves straight
    /// lines in that plane — and Natural Earth splits every polygon at the antimeridian,
    /// so no ring wraps.
    func countryCode(at coordinate: Coordinate) -> String? {
        for country in countries {
            guard let code = country.countryCode, country.box.contains(coordinate) else { continue }
            var inside = false
            for ring in country.rings where ring.box.contains(coordinate) {
                if Self.ring(ring.coordinates, contains: coordinate) {
                    // An outer ring puts the point in the country; a hole inside it
                    // takes it back out, which is what even-odd parity does.
                    inside.toggle()
                }
            }
            if inside {
                return code
            }
        }
        return nil
    }

    /// The country containing `coordinate`, or failing that the one with the nearest
    /// outline vertex within `toleranceKm` — for a pin dropped on a beach that the
    /// generalised coastline puts a few hundred metres out to sea.
    func countryCode(near coordinate: Coordinate, toleranceKm: Double) -> String? {
        if let exact = countryCode(at: coordinate) {
            return exact
        }
        let degrees = toleranceKm / 111.0 + 0.5
        var best: (code: String, distance: Double)?
        for country in countries {
            guard let code = country.countryCode,
                  country.box.contains(coordinate, margin: degrees) else {
                continue
            }
            for ring in country.rings where ring.role == .outer && ring.box.contains(
                coordinate,
                margin: degrees
            ) {
                for vertex in ring.coordinates {
                    let distance = GreatCircle.distanceKm(from: coordinate, to: vertex)
                    if distance <= toleranceKm, distance < (best?.distance ?? .infinity) {
                        best = (code, distance)
                    }
                }
            }
        }
        return best?.code
    }

    /// Natural Earth closes a ring that reaches the antimeridian along longitude +180,
    /// but `Coordinate` keeps longitudes in [-180, 180) and so stores that edge as -180,
    /// on the far side of the map. A ring otherwise in the eastern hemisphere takes its
    /// -180 vertices back to +180 here, or Chukotka and Fiji's eastern islands would
    /// resolve to no country at all.
    static func ring(_ points: [Coordinate], contains coordinate: Coordinate) -> Bool {
        guard points.count > 2 else { return false }
        let x = coordinate.longitude
        let y = coordinate.latitude
        let isEastern = points.contains { $0.longitude > 0 }
            && points.contains { $0.longitude == -180 }
        func longitude(of point: Coordinate) -> Double {
            isEastern && point.longitude == -180 ? 180 : point.longitude
        }
        var inside = false
        var previous = points[points.count - 1]
        for current in points {
            let (xi, yi) = (longitude(of: current), current.latitude)
            let (xj, yj) = (longitude(of: previous), previous.latitude)
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }
}

extension BoundingBox {
    func contains(_ coordinate: Coordinate, margin: Double = 0) -> Bool {
        coordinate.latitude >= minimumLatitude - margin
            && coordinate.latitude <= maximumLatitude + margin
            && coordinate.longitude >= minimumLongitude - margin
            && coordinate.longitude <= maximumLongitude + margin
    }
}
