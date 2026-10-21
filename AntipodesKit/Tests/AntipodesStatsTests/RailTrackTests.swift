import AntipodesCore
import AntipodesStats
import Testing

@Suite("Rail along the track")
struct RailTrackTests {
    /// Oslo to Stockholm by a track that the railway map runs through Norway, Sweden,
    /// briefly Norway again and back into Sweden: three borders, two countries. The
    /// Oslo–Bergen leg has no track, so it counts its ends: no border.
    @Test("Borders are counted along the track where the railway map gives one")
    func bordersAlongTrack() {
        let across = JourneyFixtures.leg(
            .rail,
            JourneyFixtures.oslo,
            JourneyFixtures.stockholm,
            on: "2024-06-01"
        )
        let west = JourneyFixtures.leg(
            .rail,
            JourneyFixtures.oslo,
            JourneyFixtures.bergen,
            on: "2024-06-05"
        )
        let log = TravelLog(journeys: [Journey(legs: [across]), Journey(legs: [west])])
        let along = [across.id: ["NO", "SE", "NO", "SE"]]
        let rail = RailStatistics.compute(for: log, countriesAlong: along)
        #expect(rail.bordersCrossed == 3)
        #expect(rail.countries == ["NO", "SE"])
        let overland = JourneyStatistics.compute(for: log, countriesAlong: along)
        #expect(overland.bordersCrossedOverland == 3)
        // A country the track passes through counts as reached overland.
        let viaDenmark = JourneyStatistics.compute(
            for: log,
            countriesAlong: [across.id: ["NO", "DK", "SE"]]
        )
        #expect(viaDenmark.countriesOverland == ["NO", "DK", "SE"])
        #expect(viaDenmark.bordersCrossedOverland == 2)
    }
}
