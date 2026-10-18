import AntipodesCore
import AntipodesGlobe
import Foundation
import Testing

@Suite("Globe timeline")
struct GlobeTimelineTests {
    @Test("An empty log has no timeline and nothing to apologise for")
    func emptyLog() {
        let timeline = GlobeTimeline(log: .empty, rules: .default)

        #expect(timeline.isEmpty)
        #expect(timeline.earliest == nil)
        #expect(timeline.latest == nil)
        #expect(timeline.caveat == nil)
        #expect(timeline.date(atProgress: 0.5) == nil)
    }

    /// The scrubber stops on days something happened, so three visits give three stops
    /// however far apart they are. Two visits on the same day are one stop.
    @Test("Stops are the distinct days with something on them, in order")
    func stopsAreDistinctDays() throws {
        let log = try TravelLog(visits: [
            Visit(place: GlobeFixtures.tokyo, date: GlobeFixtures.dated(2024, 9, 1)),
            Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2022, 3, 4)),
            Visit(place: GlobeFixtures.rome, date: GlobeFixtures.dated(2024, 9, 1)),
        ])
        let timeline = GlobeTimeline(log: log, rules: .default)

        #expect(timeline.stops.count == 2)
        #expect(try timeline.earliest == (GlobeFixtures.day(2022, 3, 4)))
        #expect(try timeline.latest == (GlobeFixtures.day(2024, 9, 1)))
    }

    @Test("Journeys put their own days on the timeline")
    func legsContributeStops() throws {
        let leg = try JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome,
            date: GlobeFixtures.dated(2023, 5, 10)
        )
        let log = try TravelLog(
            visits: [Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2023, 5, 9))],
            journeys: [Journey(legs: [leg])]
        )
        let timeline = GlobeTimeline(log: log, rules: .default)

        #expect(timeline.stops.count == 2)
        #expect(try timeline.latest == (GlobeFixtures.day(2023, 5, 10)))
    }

    /// Undated records cannot sit anywhere on a timeline. The screen says how many,
    /// rather than quietly showing a replay that is missing a third of someone's life.
    @Test("Undated records are counted and explained, not hidden")
    func undatedRecordsAreCounted() throws {
        let undatedLeg = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome,
            date: .unknown
        )
        let log = try TravelLog(
            visits: [
                Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2024, 1, 1)),
                Visit(place: GlobeFixtures.rome, date: .unknown),
                Visit(place: GlobeFixtures.tokyo, date: .unknown),
            ],
            journeys: [Journey(legs: [undatedLeg])]
        )
        let timeline = GlobeTimeline(log: log, rules: .default)

        #expect(timeline.stops.count == 1)
        #expect(timeline.undatedVisitCount == 2)
        #expect(timeline.undatedLegCount == 1)
        #expect(timeline.undatedCount == 3)
        #expect(timeline.caveat == "3 records have no date and cannot be placed in the replay.")
    }

    @Test("One undated record is described in the singular")
    func singularCaveat() throws {
        let log = try TravelLog(visits: [
            Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2024, 1, 1)),
            Visit(place: GlobeFixtures.rome, date: .unknown),
        ])
        let timeline = GlobeTimeline(log: log, rules: .default)

        #expect(timeline.caveat == "1 record has no date and cannot be placed in the replay.")
    }

    /// A year-only date is placed at the first day it could mean, matching how every
    /// other ordering in the app treats imprecision.
    @Test("An imprecise date lands on its earliest possible day")
    func imprecisionUsesEarliestDay() throws {
        let log = TravelLog(visits: [Visit(place: GlobeFixtures.oslo, date: .year(2024))])
        let timeline = GlobeTimeline(log: log, rules: .default)

        #expect(try timeline.stops == [GlobeFixtures.day(2024, 1, 1)])
        #expect(timeline.undatedCount == 0)
    }

    @Test("Progress runs from the first stop to the last")
    func progressMapsToStops() throws {
        let log = try TravelLog(visits: [
            Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2020, 1, 1)),
            Visit(place: GlobeFixtures.rome, date: GlobeFixtures.dated(2022, 1, 1)),
            Visit(place: GlobeFixtures.tokyo, date: GlobeFixtures.dated(2024, 1, 1)),
        ])
        let timeline = GlobeTimeline(log: log, rules: .default)

        #expect(try timeline.date(atProgress: 0) == (GlobeFixtures.day(2020, 1, 1)))
        #expect(try timeline.date(atProgress: 0.5) == (GlobeFixtures.day(2022, 1, 1)))
        #expect(try timeline.date(atProgress: 1) == (GlobeFixtures.day(2024, 1, 1)))
        // Out-of-range input is clamped rather than crashing a scrubber mid-drag.
        #expect(try timeline.date(atProgress: -5) == (GlobeFixtures.day(2020, 1, 1)))
        #expect(try timeline.date(atProgress: 5) == (GlobeFixtures.day(2024, 1, 1)))
    }

    @Test("Indexing by position is clamped to the stops that exist")
    func indexingIsClamped() throws {
        let log = try TravelLog(visits: [
            Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2020, 1, 1)),
            Visit(place: GlobeFixtures.rome, date: GlobeFixtures.dated(2022, 1, 1)),
        ])
        let timeline = GlobeTimeline(log: log, rules: .default)

        #expect(timeline.index(ofProgress: 0) == 0)
        #expect(timeline.index(ofProgress: 1) == 1)
        #expect(timeline.date(atIndex: 7) == nil)
        #expect(timeline.date(atIndex: -1) == nil)
    }

    @Test("Year markers label where each year starts on the scrubber")
    func yearMarkers() throws {
        let log = try TravelLog(visits: [
            Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2022, 3, 1)),
            Visit(place: GlobeFixtures.rome, date: GlobeFixtures.dated(2022, 8, 1)),
            Visit(place: GlobeFixtures.tokyo, date: GlobeFixtures.dated(2024, 2, 1)),
        ])
        let markers = GlobeTimeline(log: log, rules: .default).yearMarkers

        #expect(markers.count == 2)
        #expect(markers[0].year == 2022)
        #expect(markers[0].index == 0)
        #expect(markers[1].year == 2024)
        #expect(markers[1].index == 2)
    }

    @Test("The timeline honours the year and trip filters the globe is using")
    func filtersApply() throws {
        let trip = UUID()
        let log = try TravelLog(visits: [
            Visit(
                place: GlobeFixtures.oslo,
                date: GlobeFixtures.dated(2023, 1, 1),
                tripID: trip
            ),
            Visit(place: GlobeFixtures.rome, date: GlobeFixtures.dated(2024, 1, 1)),
        ])

        let byYear = GlobeTimeline(log: log, rules: .default, filter: GlobeFilter(year: 2024))
        #expect(try byYear.stops == [GlobeFixtures.day(2024, 1, 1)])

        let byTrip = GlobeTimeline(log: log, rules: .default, filter: GlobeFilter(tripID: trip))
        #expect(try byTrip.stops == [GlobeFixtures.day(2023, 1, 1)])
    }

    /// The timeline covers the same legs the arcs do, so scrubbing cannot stop on a day
    /// where nothing appears.
    @Test("A commute excluded from the globe is not a stop on the timeline either")
    func commutesFollowTheRules() throws {
        let commute = try JourneyLeg(
            mode: .rail,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome,
            date: GlobeFixtures.dated(2024, 4, 4),
            purpose: .commute
        )
        let log = TravelLog(journeys: [Journey(legs: [commute])])

        #expect(GlobeTimeline(log: log, rules: .default).isEmpty)
        #expect(!GlobeTimeline(log: log, rules: CountingRules(includeCommutes: true)).isEmpty)
    }
}
