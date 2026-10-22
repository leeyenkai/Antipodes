import AntipodesCore
import Foundation
import Testing

/// Figures and records that arrive damaged — typed by mistake, imported from a stranger
/// file, restored from a corrupt backup — are refused where they enter, rather than
/// crashing the screens that later format them.
@Suite("Record safety")
struct RecordSafetyTests {
    static let oslo = PlaceReference(
        id: .database(.city, 3_143_244),
        kind: .city,
        name: "Oslo",
        coordinate: Coordinate(latitude: 59.913, longitude: 10.752),
        countryCode: "NO"
    )
    static let bergen = PlaceReference(
        id: .database(.city, 3_161_732),
        kind: .city,
        name: "Bergen",
        coordinate: Coordinate(latitude: 60.393, longitude: 5.324),
        countryCode: "NO"
    )

    /// Infinity once reached the store through a typed "inf", and every launch then
    /// trapped converting the total to an integer.
    @Test("An impossible distance or duration is not kept on a leg")
    func implausibleFigures() {
        let leg = JourneyLeg(
            mode: .rail,
            origin: Self.oslo,
            destination: Self.bergen,
            storedPathLengthKm: .infinity,
            distanceKmOverride: 1e20,
            durationMinutesOverride: Int.max
        )
        #expect(leg.storedPathLengthKm == nil)
        #expect(leg.distanceKmOverride == nil)
        #expect(leg.durationMinutesOverride == nil)
        // It falls back to the straight line, flagged approximate, not to nothing.
        #expect(leg.distanceSource == .greatCircleApproximate)
        #expect(leg.distanceKm.isFinite)

        // A real figure is kept; the longest scheduled flight is about 15,000 km.
        let real = JourneyLeg(
            mode: .flight,
            origin: Self.oslo,
            destination: Self.bergen,
            distanceKmOverride: 15349
        )
        #expect(real.distanceKm == 15349)
    }

    @Test("A field set after creation is checked when it is read")
    func implausibleAfterCreation() {
        var leg = JourneyLeg(mode: .rail, origin: Self.oslo, destination: Self.bergen)
        leg.distanceKmOverride = .nan
        leg.storedPathLengthKm = -4
        #expect(leg.distanceSource == .greatCircleApproximate)
    }

    @Test("A backup cannot carry a date that does not exist, or a point off the Earth")
    func damagedBackups() {
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            try decoder.decode(
                CalendarDate.self,
                from: Data(#"{"year":2024,"month":13,"day":1}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(
                CalendarDate.self,
                from: Data(#"{"year":900000000000,"month":1,"day":1}"#.utf8)
            )
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(Coordinate.self, from: Data(#"{"latitude":400,"longitude":0}"#.utf8))
        }
        let good = try? decoder.decode(
            CalendarDate.self,
            from: Data(#"{"year":2024,"month":2,"day":29}"#.utf8)
        )
        #expect(good == CalendarDate(year: 2024, month: 2, day: 29))
    }

    @Test("A restored visit's rating stays within one to five stars")
    func restoredRating() throws {
        let visit = Visit(place: Self.oslo, rating: 3)
        var json = try #require(String(data: JSONEncoder().encode(visit), encoding: .utf8))
        json = json.replacingOccurrences(of: #""rating":3"#, with: #""rating":4000"#)
        let restored = try JSONDecoder().decode(Visit.self, from: Data(json.utf8))
        #expect(restored.rating == 5)
    }

    /// An editor opened just after launch holds a leg from before its rail length was
    /// measured (D-30); saving it must not write the measurement away again.
    @Test("Saving an older copy of a leg keeps the length measured since")
    func keepsMeasurement() {
        let draft = JourneyLeg(mode: .rail, origin: Self.oslo, destination: Self.bergen)
        var measured = draft
        measured.storedPathLengthKm = 448
        measured.networkVersion = "naturalearth-v5.1.2"

        let saved = draft.keepingMeasurement(from: [measured])
        #expect(saved.storedPathLengthKm == 448)
        #expect(saved.networkVersion == "naturalearth-v5.1.2")

        // Moved to another destination, it is a different leg to measure.
        var moved = draft
        moved.destination = Self.oslo
        #expect(moved.keepingMeasurement(from: [measured]).storedPathLengthKm == nil)
    }
}
