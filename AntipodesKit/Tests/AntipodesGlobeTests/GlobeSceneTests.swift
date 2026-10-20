import AntipodesCore
import AntipodesGlobe
import Foundation
import Testing

/// A small hand-built log, so every count in these tests can be worked out on paper.
enum GlobeFixtures {
    static func city(
        _ name: String,
        _ iso2: String?,
        _ coordinate: Coordinate,
        id: Int64
    ) -> PlaceReference {
        PlaceReference(
            id: .database(.city, id),
            kind: .city,
            name: name,
            coordinate: coordinate,
            countryCode: iso2,
            countryName: iso2,
            cityID: id,
            cityName: name
        )
    }

    /// A place the user logged but which has no coordinate yet — a custom pin whose
    /// geocoding has not run, which the globe cannot draw.
    static func placeWithoutCoordinate(_ name: String, _ iso2: String?) -> PlaceReference {
        PlaceReference(
            id: .custom(UUID()),
            kind: .custom,
            name: name,
            coordinate: nil,
            countryCode: iso2
        )
    }

    // Held separately as non-optional values: a test file must not force-unwrap, because
    // SwiftFormat rewrites `foo!` into `#require(foo)` and nests the macro (AGENTS.md §8).
    static let osloCoordinate = Coordinate(latitude: 59.9139, longitude: 10.7522)
    static let romeCoordinate = Coordinate(latitude: 41.9028, longitude: 12.4964)
    static let tokyoCoordinate = Coordinate(latitude: 35.6762, longitude: 139.6503)
    static let londonCoordinate = Coordinate(latitude: 51.5072, longitude: -0.1276)

    static let oslo = city("Oslo", "NO", osloCoordinate, id: 1)
    static let rome = city("Rome", "IT", romeCoordinate, id: 2)
    static let tokyo = city("Tokyo", "JP", tokyoCoordinate, id: 3)
    static let london = city("London", "GB", londonCoordinate, id: 4)

    static func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> CalendarDate {
        try #require(CalendarDate(year: year, month: month, day: dayOfMonth))
    }

    static func dated(_ year: Int, _ month: Int, _ dayOfMonth: Int) throws -> FlexibleDate {
        try .day(day(year, month, dayOfMonth))
    }
}

@Suite("Globe scene")
struct GlobeSceneTests {
    @Test("An empty log draws nothing and complains about nothing")
    func emptyLog() {
        let scene = GlobeSceneBuilder.build(log: .empty, rules: .default)

        #expect(scene.isEmpty)
        #expect(scene.pinSummary.isComplete)
        #expect(scene.pinSummary.considered == 0)
        #expect(scene.shadingSummary.caveat == nil)
    }

    @Test("A visit becomes a pin and shades its country")
    func visitBecomesPin() throws {
        let log = TravelLog(visits: [Visit(place: GlobeFixtures.oslo, visitType: .stayed)])
        let scene = GlobeSceneBuilder.build(log: log, rules: .default)

        #expect(scene.pins.count == 1)
        let pin = try #require(scene.pins.first)
        #expect(pin.style == .visited)
        #expect(scene.shadedCountryCodes == ["NO"])
    }

    /// The globe must agree with the number printed beside it: a layover does not count
    /// towards coverage by default, so it must not shade the country either (R-CALC-1).
    @Test("A layover is pinned but does not shade its country under the default rules")
    func layoverIsNotCounted() throws {
        let log = TravelLog(visits: [Visit(place: GlobeFixtures.tokyo, visitType: .layover)])
        let scene = GlobeSceneBuilder.build(log: log, rules: .default)

        let pin = try #require(scene.pins.first)
        #expect(pin.style == .notCounted)
        #expect(scene.shadedCountryCodes.isEmpty)
    }

    @Test("Turning layovers on shades the country and promotes the pin")
    func layoverCountedWhenRulesSaySo() throws {
        let log = TravelLog(visits: [Visit(place: GlobeFixtures.tokyo, visitType: .layover)])
        let rules = CountingRules(includeLayovers: true)
        let scene = GlobeSceneBuilder.build(log: log, rules: rules)

        let pin = try #require(scene.pins.first)
        #expect(pin.style == .visited)
        #expect(scene.shadedCountryCodes == ["JP"])
    }

    @Test("A visit with no coordinate is counted as undrawable, not dropped in silence")
    func visitWithoutCoordinate() {
        let log = TravelLog(visits: [
            Visit(place: GlobeFixtures.oslo),
            Visit(place: GlobeFixtures.placeWithoutCoordinate("Grandmother's house", "NO")),
        ])
        let scene = GlobeSceneBuilder.build(log: log, rules: .default)

        #expect(scene.pins.count == 1)
        #expect(scene.pinSummary.considered == 2)
        #expect(scene.pinSummary.used == 1)
        #expect(scene.pinSummary.exclusions[.missingCoordinate] == 1)
        #expect(scene.pinSummary.caveat != nil)
        // It still shades Norway: a visit can have a country without a coordinate.
        #expect(scene.shadedCountryCodes == ["NO"])
    }

    @Test("A visit with no country is counted against the shading, not the pins")
    func visitWithoutCountry() {
        let place = PlaceReference(
            id: .custom(UUID()),
            kind: .custom,
            name: "A dot in the Pacific",
            coordinate: Coordinate(latitude: -10, longitude: -150),
            countryCode: nil
        )
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(visits: [Visit(place: place)]),
            rules: .default
        )

        #expect(scene.pins.count == 1)
        #expect(scene.pinSummary.isComplete)
        #expect(scene.shadedCountryCodes.isEmpty)
        #expect(scene.shadingSummary.exclusions[.missingCountry] == 1)
    }

    // MARK: - Arcs

    /// The drawn arc has to start and end exactly where the leg does, because the same
    /// curve is what the distance was measured along (R-PATH-4, AGENTS.md §7).
    @Test("An arc runs from the leg's origin to its destination, along the great circle")
    func arcMatchesTheLeg() throws {
        let leg = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.tokyo
        )
        let log = TravelLog(journeys: [Journey(legs: [leg])])
        let scene = GlobeSceneBuilder.build(log: log, rules: .default)

        let arc = try #require(scene.arcs.first)
        let start = try #require(arc.path.first)
        let end = try #require(arc.path.last)
        #expect(start == GlobeFixtures.oslo.coordinate)
        #expect(end == GlobeFixtures.tokyo.coordinate)
        #expect(arc.path.count == GlobeSceneBuilder.defaultArcSegments + 1)

        // The middle of the path is on the great circle, not on the straight line
        // between the endpoints: Oslo to Tokyo goes over the Arctic, well north of
        // either city.
        let middle = arc.path[arc.path.count / 2]
        #expect(middle.latitude > GlobeFixtures.osloCoordinate.latitude)
    }

    @Test("A leg with an endpoint that has no coordinate cannot be drawn, and says so")
    func arcWithoutCoordinates() {
        let leg = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.placeWithoutCoordinate("Somewhere", "SE")
        )
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(journeys: [Journey(legs: [leg])]),
            rules: .default
        )

        #expect(scene.arcs.isEmpty)
        #expect(scene.arcSummary.exclusions[.missingCoordinate] == 1)
    }

    /// If the distance stat leaves commutes out, the globe has to as well, or the
    /// picture and the total describe different sets of journeys (Q-15).
    @Test("Commutes follow the stats setting")
    func commutesFollowTheRules() {
        let leg = JourneyLeg(
            mode: .rail,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome,
            purpose: .commute
        )
        let log = TravelLog(journeys: [Journey(legs: [leg])])

        let excluded = GlobeSceneBuilder.build(log: log, rules: .default)
        #expect(excluded.arcs.isEmpty)
        #expect(excluded.arcSummary.exclusions[.commuteExcluded] == 1)

        let included = GlobeSceneBuilder.build(
            log: log,
            rules: CountingRules(includeCommutes: true)
        )
        #expect(included.arcs.count == 1)
    }

    /// The number beside the globe has to describe the globe. Summed from each leg's
    /// own resolved distance, so it agrees with the distance stat leg for leg rather
    /// than being a second opinion computed from coordinates.
    @Test("The scene totals the distance of the arcs it actually drew")
    func sceneTotalsItsOwnDistance() {
        let osloToRome = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome
        )
        let romeToTokyo = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.rome,
            destination: GlobeFixtures.tokyo
        )
        let log = TravelLog(journeys: [Journey(legs: [osloToRome, romeToTokyo])])
        let scene = GlobeSceneBuilder.build(log: log, rules: .default)

        let expected = osloToRome.distanceKm + romeToTokyo.distanceKm
        #expect(abs(scene.totalDistanceKm - expected) < 0.001)
        #expect(expected > 0)
    }

    /// Filter to one mode and the total follows, rather than still reporting a lifetime
    /// figure beside a globe showing one flight.
    @Test("Filtering narrows the distance total with the arcs")
    func distanceFollowsTheFilter() {
        let flight = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.tokyo
        )
        let train = JourneyLeg(
            mode: .rail,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome
        )
        let log = TravelLog(journeys: [Journey(legs: [flight, train])])

        let everything = GlobeSceneBuilder.build(log: log, rules: .default)
        let flightsOnly = GlobeSceneBuilder.build(
            log: log,
            rules: .default,
            filter: GlobeFilter(mode: .flight)
        )

        #expect(abs(everything.totalDistanceKm - (flight.distanceKm + train.distanceKm)) < 0.001)
        #expect(abs(flightsOnly.totalDistanceKm - flight.distanceKm) < 0.001)
    }

    @Test("A leg with no distance available adds nothing to the total")
    func unavailableDistanceAddsNothing() {
        let leg = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.placeWithoutCoordinate("Somewhere", "SE")
        )
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(journeys: [Journey(legs: [leg])]),
            rules: .default
        )

        #expect(scene.totalDistanceKm == 0)
    }

    // MARK: - Filters

    @Test("The year filter keeps that year, and filtering is not an exclusion")
    func yearFilter() {
        let log = TravelLog(visits: [
            Visit(place: GlobeFixtures.oslo, date: .year(2023)),
            Visit(place: GlobeFixtures.rome, date: .year(2024)),
            Visit(place: GlobeFixtures.tokyo, date: .year(2024)),
        ])
        let scene = GlobeSceneBuilder.build(
            log: log,
            rules: .default,
            filter: GlobeFilter(year: 2024)
        )

        #expect(scene.pins.count == 2)
        // A record the user filtered out is not a record the globe failed to draw.
        #expect(scene.pinSummary.considered == 2)
        #expect(scene.pinSummary.isComplete)
    }

    @Test("The trip filter keeps that trip's visits and journeys")
    func tripFilter() {
        let trip = UUID()
        let other = UUID()
        let thisTrip = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome
        )
        let otherTrip = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.rome,
            destination: GlobeFixtures.tokyo
        )
        let log = TravelLog(
            visits: [
                Visit(place: GlobeFixtures.oslo, tripID: trip),
                Visit(place: GlobeFixtures.rome, tripID: other),
            ],
            journeys: [
                Journey(legs: [thisTrip], tripID: trip),
                Journey(legs: [otherTrip], tripID: other),
            ]
        )
        let scene = GlobeSceneBuilder.build(
            log: log,
            rules: .default,
            filter: GlobeFilter(tripID: trip)
        )

        #expect(scene.pins.count == 1)
        #expect(scene.arcs.count == 1)
    }

    /// A visit has no mode, so filtering to flights still shows where you have been —
    /// otherwise the globe would empty out and look broken.
    @Test("The mode filter narrows the arcs but leaves the pins alone")
    func modeFilterAppliesToArcsOnly() {
        let flight = JourneyLeg(
            mode: .flight,
            origin: GlobeFixtures.oslo,
            destination: GlobeFixtures.rome
        )
        let train = JourneyLeg(
            mode: .rail,
            origin: GlobeFixtures.rome,
            destination: GlobeFixtures.london
        )
        let log = TravelLog(
            visits: [Visit(place: GlobeFixtures.oslo), Visit(place: GlobeFixtures.rome)],
            journeys: [Journey(legs: [flight]), Journey(legs: [train])]
        )
        let scene = GlobeSceneBuilder.build(
            log: log,
            rules: .default,
            filter: GlobeFilter(mode: .flight)
        )

        #expect(scene.arcs.count == 1)
        #expect(scene.arcs.first?.mode == .flight)
        #expect(scene.pins.count == 2)
    }

    // MARK: - Replay

    @Test("Scrubbing the replay back in time hides what had not happened yet")
    func replayHidesLaterVisits() throws {
        let log = try TravelLog(visits: [
            Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2024, 3, 1)),
            Visit(place: GlobeFixtures.rome, date: GlobeFixtures.dated(2024, 6, 1)),
            Visit(place: GlobeFixtures.tokyo, date: GlobeFixtures.dated(2024, 9, 1)),
        ])
        let scene = try GlobeSceneBuilder.build(
            log: log,
            rules: .default,
            filter: GlobeFilter(replayUpTo: GlobeFixtures.day(2024, 6, 1))
        )

        // Inclusive of the day itself: Oslo and Rome, not Tokyo.
        #expect(scene.pins.count == 2)
        #expect(scene.shadedCountryCodes == ["NO", "IT"])
    }

    /// An undated visit cannot be placed on a timeline. During replay it has to come
    /// out of the picture, and the screen has to say how many did (R-DATE-2).
    @Test("Undated records are excluded from the replay and counted")
    func replayCountsUndatedRecords() throws {
        let log = try TravelLog(visits: [
            Visit(place: GlobeFixtures.oslo, date: GlobeFixtures.dated(2024, 3, 1)),
            Visit(place: GlobeFixtures.rome, date: .unknown),
        ])

        let replaying = try GlobeSceneBuilder.build(
            log: log,
            rules: .default,
            filter: GlobeFilter(replayUpTo: GlobeFixtures.day(2024, 12, 31))
        )
        #expect(replaying.pins.count == 1)
        #expect(replaying.pinSummary.exclusions[.unknownDate] == 1)
        #expect(replaying.shadingSummary.exclusions[.unknownDate] == 1)

        // With the replay parked, an undated visit is shown like any other.
        let whole = GlobeSceneBuilder.build(log: log, rules: .default)
        #expect(whole.pins.count == 2)
        #expect(whole.pinSummary.isComplete)
    }

    /// A year-precision date sorts by its earliest possible day, so "2024" counts as
    /// 1 January 2024 for the replay and never jumps ahead of something dated.
    @Test("An imprecise date is placed at the earliest day it could mean")
    func replayUsesEarliestPossibleDay() throws {
        let log = TravelLog(visits: [Visit(place: GlobeFixtures.oslo, date: .year(2024))])

        let before = try GlobeSceneBuilder.build(
            log: log,
            rules: .default,
            filter: GlobeFilter(replayUpTo: GlobeFixtures.day(2023, 12, 31))
        )
        let after = try GlobeSceneBuilder.build(
            log: log,
            rules: .default,
            filter: GlobeFilter(replayUpTo: GlobeFixtures.day(2024, 1, 1))
        )

        #expect(before.pins.isEmpty)
        #expect(after.pins.count == 1)
    }

    // MARK: - The wishlist seam

    /// Wishlist places are passed in and styled as wishlist pins rather than visits
    /// (R-GLOBE-4).
    @Test("Wishlist places are pinned in their own style and never shade a country")
    func wishlistPinsAreDistinct() throws {
        let scene = GlobeSceneBuilder.build(
            log: TravelLog(visits: [Visit(place: GlobeFixtures.oslo)]),
            rules: .default,
            wishlist: [GlobeFixtures.tokyo]
        )

        #expect(scene.pins.count == 2)
        let wishlist = try #require(scene.pins.first { $0.style == .wishlist })
        #expect(wishlist.place.name == "Tokyo")
        #expect(wishlist.visitType == nil)
        // Wanting to go to Japan does not mean having been there.
        #expect(scene.shadedCountryCodes == ["NO"])
    }

    /// A selected wishlist pin must stay selected when the scene is rebuilt after an
    /// unrelated edit, so its identity cannot be a fresh UUID each time.
    @Test("A wishlist pin keeps its identity across rebuilds, and differs between places")
    func wishlistPinIdentityIsStable() {
        func wishlistPinIDs() -> [UUID] {
            GlobeSceneBuilder.build(
                log: .empty,
                rules: .default,
                wishlist: [GlobeFixtures.tokyo, GlobeFixtures.oslo]
            ).pins.map(\.id)
        }
        let first = wishlistPinIDs()
        #expect(first == wishlistPinIDs())
        #expect(Set(first).count == 2)
    }
}
