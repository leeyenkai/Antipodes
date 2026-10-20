import AntipodesCore
@testable import AntipodesStats
import Foundation
import Testing

/// Rules that cut across families: what a place implies, which year a record belongs
/// to, what counts as having ridden a route, and how badges date themselves.
@Suite("Cross-family correctness")
struct CorrectnessTests {
    static let paris = Fixtures.city(
        "Paris", "FR", "France", .europe,
        id: 2_988_507, latitude: 48.8566, longitude: 2.3522
    )
    static let eiffel = Fixtures.landmark(
        "Eiffel Tower", "FR", "France", .europe,
        id: 243, cityID: 2_988_507, cityName: "Paris",
        latitude: 48.8584, longitude: 2.2945
    )
    static let heathrow = PlaceReference(
        id: .database(.airport, 2434),
        kind: .airport,
        name: "London Heathrow",
        coordinate: Coordinate(latitude: 51.47, longitude: -0.4543),
        countryCode: "GB",
        countryName: "United Kingdom",
        continent: .europe,
        cityID: 2_643_743,
        cityName: "London",
        code: "LHR"
    )

    static func day(_ iso: String) throws -> FlexibleDate {
        try .day(#require(CalendarDate(iso: iso)))
    }

    // MARK: - What a place implies (R-MODEL-6)

    /// Logging only the Eiffel Tower implies Paris, so the app must fetch Paris's facts
    /// — or Paris never counts as a capital.
    @Test("A landmark's city is among the places the log needs facts for")
    func impliedCityNeedsFacts() {
        let log = TravelLog(visits: [Visit(place: Self.eiffel)])
        #expect(log.referencedDatabasePlaceIDs == [Self.eiffel.id, Self.paris.id])

        let gazetteer = Gazetteer(places: [Self.paris.id: PlaceFacts(isCapital: true)])
        let coverage = CoverageStatistics.compute(for: log, gazetteer: gazetteer)
        #expect(coverage.citiesVisited == 1)
        #expect(coverage.capitalsVisited == 1)
    }

    /// An airport records the city it serves, but R-MODEL-6 does not chain through
    /// airports: changing planes at Heathrow is not a visit to London.
    @Test("An airport implies its country, never its city")
    func airportImpliesNoCity() {
        var rules = CountingRules.default
        rules.includePassedThrough = true
        rules.includeLayovers = true
        let log = TravelLog(visits: [Visit(place: Self.heathrow, visitType: .layover)])
        let coverage = CoverageStatistics.compute(for: log, rules: rules)
        #expect(Self.heathrow.impliedCityID == nil)
        #expect(coverage.countryCodes == ["GB"])
        #expect(coverage.citiesVisited == 0)
        #expect(log.referencedDatabasePlaceIDs == [Self.heathrow.id])
    }

    // MARK: - Which year (D-23)

    /// One visit on 28 Dec 2024–3 Jan 2025 and one undated: 2024 has one visit, 2025
    /// none, and the undated one is reported rather than lost.
    @Test("Visits per year file a New Year range once, and report the undated")
    func visitsByYear() throws {
        let holiday = try FlexibleDate.span(
            #require(CalendarDate(iso: "2024-12-28")),
            #require(CalendarDate(iso: "2025-01-03"))
        )
        let log = TravelLog(visits: [
            Visit(place: Self.paris, date: holiday),
            Visit(place: Self.paris),
        ])
        let time = try TimeStatistics.compute(
            for: log,
            today: #require(CalendarDate(iso: "2026-10-21"))
        )
        #expect(time.visitsByYear == [2024: 1])
        #expect(time.newCountriesByYear == [2024: ["FR"]])
        #expect(time.yearInput.used == 1)
        #expect(time.yearInput.exclusions == [.unknownDate: 1])
        // Seasonality files the range under December, the month it began.
        #expect(time.visitsByMonth == [12: 1])
    }

    /// An undated visit to France might have been before 2026, so a dated 2026 visit
    /// cannot claim France as new — but it is reported as possibly new, not dropped.
    @Test("Year in Review does not call a country new when an undated visit might precede it")
    func newCountriesWithUndatedVisit() throws {
        let log = try TravelLog(visits: [
            Visit(place: Self.paris),
            Visit(place: Self.paris, date: Self.day("2026-05-01")),
            Visit(place: Fixtures.osl, date: Self.day("2026-06-01")),
        ])
        var rules = CountingRules.default
        rules.includePassedThrough = true
        rules.includeLayovers = true
        let review = YearInReview.compute(year: 2026, log: log, rules: rules)
        #expect(review.newCountries == ["NO"])
        #expect(review.possiblyNewCountries == ["FR"])
    }

    // MARK: - Routes (R-JLOG-3)

    static let bergen = Fixtures.city(
        "Bergen",
        "NO",
        "Norway",
        .europe,
        id: 3_161_732,
        latitude: 60.39,
        longitude: 5.32
    )
    static let oslo = Fixtures.city(
        "Oslo",
        "NO",
        "Norway",
        .europe,
        id: 3_143_244,
        latitude: 59.91,
        longitude: 10.75
    )
    static let finse = PlaceReference(id: .custom(UUID()), kind: .custom, name: "Finse")
    static let bergenLine = RouteInfo(
        id: 1, name: "Bergen Line", mode: .rail,
        start: oslo, end: bergen, lengthKm: 496, highestPointM: 1237
    )

    /// Oslo to Finse rides part of the Bergen Line; it does not complete it, and does
    /// not reach its summit near Finse for certain. Bergen to Oslo, either way round,
    /// rides all of it.
    @Test("Only a whole ride of a route ticks it off or claims its highest point")
    func partialRoute() {
        let section = JourneyLeg(
            mode: .rail,
            origin: Self.oslo,
            destination: Self.finse,
            routeID: 1
        )
        let whole = JourneyLeg(mode: .rail, origin: Self.bergen, destination: Self.oslo, routeID: 1)
        let member = PlaceReference(id: .database(.route, 1), kind: .route, name: "Bergen Line")
        let collection = CollectionDefinition(id: "rail", name: "Rail", members: [member])

        func status(_ legs: [JourneyLeg]) -> (Bool, Double?) {
            let log = TravelLog(journeys: [Journey(legs: legs)])
            let progress = CollectionProgress.compute(
                collections: [collection], log: log, routes: [Self.bergenLine]
            )
            let rail = RailStatistics.compute(for: log, routes: [Self.bergenLine])
            return (progress.first?.members.first?.isVisited ?? false, rail.highestPointM)
        }
        #expect(status([section]) == (false, nil))
        #expect(status([whole]) == (true, 1237))
        #expect(Self.bergenLine.isRiddenInFull(by: whole))
        #expect(!Self.bergenLine.isRiddenInFull(by: section))
    }

    // MARK: - Badges

    static func badge(_ rule: AchievementRule, threshold: Double) -> AchievementDefinition {
        AchievementDefinition(
            id: rule.rawValue,
            name: rule.rawValue,
            description: "",
            rule: rule,
            threshold: threshold
        )
    }

    /// A trip with nothing in it is a folder, not a trip taken.
    @Test("The trips badge counts only trips with something in them")
    func emptyTripsDoNotCount() {
        let full = Trip(name: "Paris")
        let log = TravelLog(
            trips: [full, Trip(name: "Someday")],
            visits: [Visit(place: Self.paris, tripID: full.id)]
        )
        let status = AchievementEngine.evaluate([Self.badge(.trips, threshold: 2)], log: log)
        #expect(status.first?.current == 1)
        #expect(status.first?.isEarned == false)
    }

    /// A badge earned only through a visit dated "2019" has no day to show.
    @Test("A badge's earned date needs records dated to the day")
    func earnedOnPrecision() throws {
        let yearOnly = TravelLog(visits: [Visit(place: Self.paris, date: .year(2019))])
        let status = AchievementEngine.evaluate(
            [Self.badge(.countries, threshold: 1)],
            log: yearOnly
        )
        #expect(status.first?.isEarned == true)
        #expect(status.first?.earnedOn == nil)

        let exact = try TravelLog(visits: [Visit(place: Self.paris, date: Self.day("2019-06-12"))])
        let dated = AchievementEngine.evaluate([Self.badge(.countries, threshold: 1)], log: exact)
        #expect(dated.first?.earnedOn?.iso == "2019-06-12")
    }

    /// The closest-to-antipodal pair, checked against every pair measured the slow way.
    /// Madrid and Wellington are the textbook near-antipodes; the fixture adds noise.
    @Test("The antipodes badge finds the same closest pair as measuring every pair")
    func antipodesMatchesBruteForce() {
        let coordinates = [
            Coordinate(latitude: 40.4168, longitude: -3.7038), // Madrid
            Coordinate(latitude: -41.2865, longitude: 174.7762), // Wellington
            Coordinate(latitude: 51.5074, longitude: -0.1278), // London
            Coordinate(latitude: -33.8688, longitude: 151.2093), // Sydney
            Coordinate(latitude: 35.6762, longitude: 139.6503), // Tokyo
            Coordinate(latitude: -34.6037, longitude: -58.3816), // Buenos Aires
            Coordinate(latitude: 31.2304, longitude: 121.4737), // Shanghai
        ]
        let visits = coordinates.enumerated().map { index, coordinate in
            Visit(place: PlaceReference(
                id: .custom(UUID()), kind: .custom, name: "P\(index)", coordinate: coordinate
            ))
        }
        let status = AchievementEngine.evaluate(
            [Self.badge(.antipodes, threshold: 500)],
            log: TravelLog(visits: visits)
        )
        var expected = Double.infinity
        for first in coordinates.indices {
            for second in coordinates.indices where second > first {
                expected = min(expected, GreatCircle.distanceKm(
                    from: coordinates[first].antipode, to: coordinates[second]
                ))
            }
        }
        #expect(abs((status.first?.current ?? .infinity) - expected) < 1e-6)
        // Madrid's antipode is 160.3 km from Wellington (haversine on the IUGG mean
        // radius, worked separately); Shanghai and Buenos Aires come next at 375.3 km.
        #expect(abs(expected - 160.3) < 0.1)
        #expect(status.first?.isEarned == true)
    }

    /// A flight logged between two custom pins with no location has no distance, but
    /// it was still flown: it counts as a flight, not towards the kilometres.
    @Test("A flight with no distance is still a flight")
    func flightWithoutDistance() {
        let nowhere = PlaceReference(id: .custom(UUID()), kind: .custom, name: "Somewhere")
        let elsewhere = PlaceReference(id: .custom(UUID()), kind: .custom, name: "Elsewhere")
        let measured = JourneyLeg(mode: .flight, origin: Fixtures.osl, destination: Fixtures.jfk)
        let unmeasured = JourneyLeg(mode: .flight, origin: nowhere, destination: elsewhere)
        let log = TravelLog(journeys: [Journey(legs: [measured]), Journey(legs: [unmeasured])])
        let flights = FlightStatistics.compute(for: log)
        #expect(flights.flightCount == 2)
        #expect(flights.measuredFlightCount == 1)
        #expect(flights.input.exclusions == [.distanceUnavailable: 1])
        #expect(abs(flights.averageFlightKm - flights.totalKm) < 1e-9)
    }
}
