import AntipodesCore
import Foundation
import Testing

/// Reference distances are published great-circle figures for well-known airport
/// pairs. A 0.5% tolerance covers the difference between a sphere and the WGS-84
/// ellipsoid (R-PATH-4, M1 acceptance criterion 4).
@Suite("Great-circle distances")
struct GreatCircleTests {
    static let oslo = Coordinate(latitude: 60.1939, longitude: 11.1004) // OSL
    static let newYork = Coordinate(latitude: 40.6413, longitude: -73.7781) // JFK
    static let london = Coordinate(latitude: 51.4700, longitude: -0.4543) // LHR
    static let sydney = Coordinate(latitude: -33.9399, longitude: 151.1753) // SYD
    static let singapore = Coordinate(latitude: 1.3644, longitude: 103.9915) // SIN

    @Test("OSL to JFK is about 5,920 km")
    func osloToNewYork() {
        let distance = GreatCircle.distanceKm(from: Self.oslo, to: Self.newYork)
        #expect(abs(distance - 5920) / 5920 < 0.005)
    }

    @Test("LHR to JFK is about 5,540 km")
    func londonToNewYork() {
        let distance = GreatCircle.distanceKm(from: Self.london, to: Self.newYork)
        #expect(abs(distance - 5540) / 5540 < 0.005)
    }

    @Test("LHR to SYD is about 16,990 km, the classic long-haul pair")
    func londonToSydney() {
        let distance = GreatCircle.distanceKm(from: Self.london, to: Self.sydney)
        #expect(abs(distance - 16990) / 16990 < 0.005)
    }

    @Test("SIN to SYD is about 6,300 km")
    func singaporeToSydney() {
        let distance = GreatCircle.distanceKm(from: Self.singapore, to: Self.sydney)
        #expect(abs(distance - 6300) / 6300 < 0.005)
    }

    @Test("A point to itself is zero, not a rounding artefact")
    func zeroDistance() {
        #expect(GreatCircle.distanceKm(from: Self.oslo, to: Self.oslo) == 0)
    }

    /// Haversine is used precisely so short legs stay accurate — a city-transit segment
    /// is a few hundred metres, where the law of cosines loses precision.
    @Test("A 200 m segment measures as 200 m, not zero")
    func shortSegmentPrecision() {
        let start = Coordinate(latitude: 59.9139, longitude: 10.7522)
        // 0.0018° of latitude is almost exactly 200 m.
        let end = Coordinate(latitude: 59.9157, longitude: 10.7522)
        let metres = GreatCircle.distanceKm(from: start, to: end) * 1000
        #expect(abs(metres - 200) < 5)
    }

    @Test("A quarter of the Earth's circumference spans 90° of latitude")
    func quarterCircumference() {
        let equator = Coordinate(latitude: 0, longitude: 0)
        let pole = Coordinate(latitude: 90, longitude: 0)
        let expected = GreatCircle.earthCircumferenceKm / 4
        #expect(abs(GreatCircle.distanceKm(from: equator, to: pole) - expected) < 0.001)
    }

    @Test("Distance is symmetric")
    func symmetry() {
        let forward = GreatCircle.distanceKm(from: Self.oslo, to: Self.sydney)
        let backward = GreatCircle.distanceKm(from: Self.sydney, to: Self.oslo)
        #expect(abs(forward - backward) < 1e-9)
    }

    @Test("Due-north and due-east bearings come out as 0° and 90°")
    func bearings() {
        let origin = Coordinate(latitude: 0, longitude: 0)
        #expect(
            abs(GreatCircle.initialBearingDegrees(
                from: origin,
                to: Coordinate(latitude: 10, longitude: 0)
            )) < 0.001
        )
        #expect(
            abs(GreatCircle.initialBearingDegrees(
                from: origin,
                to: Coordinate(latitude: 0, longitude: 10)
            ) - 90) < 0.001
        )
    }

    @Test("Interpolating halfway along the equator lands on the midpoint")
    func interpolationMidpoint() {
        let midpoint = GreatCircle.interpolate(
            from: Coordinate(latitude: 0, longitude: 0),
            to: Coordinate(latitude: 0, longitude: 40),
            fraction: 0.5
        )
        #expect(abs(midpoint.latitude) < 1e-9)
        #expect(abs(midpoint.longitude - 20) < 1e-9)
    }

    @Test("Interpolation clamps out-of-range fractions to the endpoints")
    func interpolationClamps() {
        #expect(
            GreatCircle.interpolate(from: Self.oslo, to: Self.sydney, fraction: -1) == Self.oslo
        )
        #expect(
            GreatCircle.interpolate(from: Self.oslo, to: Self.sydney, fraction: 2) == Self.sydney
        )
    }

    /// The arc and the distance must come from the same curve, or the globe will
    /// disagree with the stats (R-PATH-5).
    @Test("The sampled arc is within 0.1% of the direct distance")
    func arcLengthMatchesDistance() {
        let direct = GreatCircle.distanceKm(from: Self.oslo, to: Self.sydney)
        let sampled = GreatCircle.pathLengthKm(
            GreatCircle.arc(from: Self.oslo, to: Self.sydney, segments: 256)
        )
        #expect(abs(sampled - direct) / direct < 0.001)
    }

    @Test("An arc starts and ends at its endpoints")
    func arcEndpoints() {
        let arc = GreatCircle.arc(from: Self.oslo, to: Self.newYork, segments: 8)
        #expect(arc.count == 9)
        #expect(arc.first == Self.oslo)
        #expect(arc.last == Self.newYork)
    }

    @Test("A path with fewer than two points has no length")
    func degeneratePaths() {
        #expect(GreatCircle.pathLengthKm([]) == 0)
        #expect(GreatCircle.pathLengthKm([Self.oslo]) == 0)
    }
}

@Suite("Coordinates")
struct CoordinateTests {
    @Test("Latitude clamps and longitude wraps")
    func normalisation() {
        #expect(Coordinate(latitude: 120, longitude: 0).latitude == 90)
        #expect(Coordinate(latitude: -120, longitude: 0).latitude == -90)
        #expect(Coordinate(latitude: 0, longitude: 200).longitude == -160)
        #expect(Coordinate(latitude: 0, longitude: -200).longitude == 160)
        #expect(Coordinate(latitude: 0, longitude: 180).longitude == -180)
    }

    @Test("Validating init rejects out-of-range input instead of clamping")
    func validatingInit() {
        #expect(Coordinate(validating: 91, 0) == nil)
        #expect(Coordinate(validating: 0, 181) == nil)
        #expect(Coordinate(validating: .nan, 0) == nil)
        #expect(Coordinate(validating: 59.9, 10.75) != nil)
    }

    /// The app is named after this, so it had better be right.
    @Test("The antipode of Oslo is in the South Pacific, and is its own inverse")
    func antipode() {
        let oslo = Coordinate(latitude: 59.9139, longitude: 10.7522)
        let antipode = oslo.antipode
        #expect(abs(antipode.latitude - -59.9139) < 1e-9)
        #expect(abs(antipode.longitude - -169.2478) < 1e-9)
        #expect(abs(antipode.antipode.latitude - oslo.latitude) < 1e-9)
        #expect(abs(antipode.antipode.longitude - oslo.longitude) < 1e-9)
    }

    @Test("An antipode is half the Earth's circumference away")
    func antipodeDistance() {
        let point = Coordinate(latitude: 35.6762, longitude: 139.6503)
        let distance = GreatCircle.distanceKm(from: point, to: point.antipode)
        #expect(abs(distance - GreatCircle.earthCircumferenceKm / 2) < 0.001)
    }

    @Test("Latitude circles used by achievements")
    func latitudeCircles() {
        #expect(Coordinate(latitude: 78.22, longitude: 15.63).isNorthOfArcticCircle)
        #expect(!Coordinate(latitude: 59.91, longitude: 10.75).isNorthOfArcticCircle)
        #expect(Coordinate(latitude: -82, longitude: 0).isSouthOfAntarcticCircle)
        #expect(Coordinate(latitude: 1.35, longitude: 103.82).isWithinTropics)
        #expect(Coordinate(latitude: 0, longitude: 0).hemisphere == .northern)
        #expect(Coordinate(latitude: -0.1, longitude: 0).hemisphere == .southern)
    }
}
