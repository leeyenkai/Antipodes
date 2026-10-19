import AntipodesCore
@testable import AntipodesGlobe
import Foundation
import Testing

/// The real 1:50m outlines, when they have been built (`scripts/build-borders.sh`).
enum BorderFixture {
    static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Tools/placedb/out/borders-50m.antborders")
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

@Suite("Point in polygon")
struct RingContainmentTests {
    /// A unit square, and a square hole inside a larger square.
    @Test("Even-odd ray casting is inside, outside and respects holes")
    func square() {
        let square = [(0.0, 0.0), (0, 10), (10, 10), (10, 0)].map { Coordinate(
            latitude: $0.0,
            longitude: $0.1
        ) }
        #expect(CountryBorders.ring(square, contains: Coordinate(latitude: 5, longitude: 5)))
        #expect(!CountryBorders.ring(square, contains: Coordinate(latitude: 15, longitude: 5)))
        #expect(!CountryBorders.ring(square, contains: Coordinate(latitude: 5, longitude: -1)))
    }
}

@Suite("Country lookup from bundled borders", .enabled(if: BorderFixture.exists))
struct BorderLookupTests {
    /// M1 acceptance criterion 3: a pin resolves to a country with no network call.
    @Test("Pins resolve to the country they are in")
    func countries() throws {
        let borders = try CountryBorders.load(from: BorderFixture.url)
        #expect(borders
            .countryCode(at: Coordinate(latitude: 63.4305, longitude: 10.3951)) ==
            "NO") // Trondheim
        #expect(borders
            .countryCode(at: Coordinate(latitude: 41.9028, longitude: 12.4964)) == "IT") // Rome
        #expect(borders
            .countryCode(at: Coordinate(latitude: -29.31, longitude: 27.48)) ==
            "LS") // Maseru, a hole in ZA
        #expect(borders
            .countryCode(at: Coordinate(latitude: -26.2, longitude: 28.04)) == "ZA") // Johannesburg
        #expect(borders
            .countryCode(at: Coordinate(latitude: 30, longitude: -40)) == nil) // mid-Atlantic
    }

    @Test("A pin just off a generalised coastline snaps to the nearest country within tolerance")
    func nearCoast() throws {
        let borders = try CountryBorders.load(from: BorderFixture.url)
        // Just off Bergen's coast, inside the tolerance but outside the 1:50m outline.
        let offshore = Coordinate(latitude: 60.39, longitude: 4.6)
        #expect(borders.countryCode(near: offshore, toleranceKm: 40) == "NO")
        #expect(borders.countryCode(
            near: Coordinate(latitude: 30, longitude: -40),
            toleranceKm: 40
        ) == nil)
    }
}
