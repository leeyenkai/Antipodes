import AntipodesCore
import AntipodesStats
import Foundation
import Testing

enum JourneyFixtures {
    static func place(
        _ name: String,
        _ country: String,
        latitude: Double,
        longitude: Double,
        zone: String?
    ) -> PlaceReference {
        PlaceReference(
            id: .custom(UUID()),
            kind: .custom,
            name: name,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            countryCode: country,
            timeZoneIdentifier: zone
        )
    }

    static let oslo = place("Oslo S", "NO", latitude: 59.91, longitude: 10.75, zone: "Europe/Oslo")
    static let bergen = place("Bergen", "NO", latitude: 60.39, longitude: 5.33, zone: "Europe/Oslo")
    static let stockholm = place(
        "Stockholm C",
        "SE",
        latitude: 59.33,
        longitude: 18.06,
        zone: "Europe/Stockholm"
    )

    static func time(_ iso: String) -> LocalDateTime {
        LocalDateTime(iso: iso)!
    }

    static func leg(
        _ mode: TravelMode,
        _ from: PlaceReference,
        _ to: PlaceReference,
        on iso: String,
        departs: String? = nil,
        arrives: String? = nil,
        actualArrival: String? = nil,
        operatorName: String? = nil,
        travelClass: String? = nil,
        distanceKm: Double? = nil
    ) -> JourneyLeg {
        JourneyLeg(
            mode: mode,
            origin: from,
            destination: to,
            date: .day(CalendarDate(iso: iso)!),
            distanceKmOverride: distanceKm,
            times: LegTimes(
                scheduledDeparture: departs.map(time),
                scheduledArrival: arrives.map(time),
                actualArrival: actualArrival.map(time)
            ),
            operatorName: operatorName,
            travelClass: travelClass
        )
    }
}

@Suite("Journey totals")
struct JourneyStatisticsTests {
    /// Rail Oslo 08:00 → Bergen 14:30, both on Oslo time: 390 minutes. Rail Oslo 16:00
    /// → Stockholm 21:00, both UTC+2 in June: 300 minutes. Two legs on 13 June. One
    /// border crossed overland, Norway to Sweden.
    @Test("Totals time by mode, find the busiest day and count borders crossed by land")
    func totals() throws {
        let log = TravelLog(journeys: [
            Journey(legs: [
                JourneyFixtures.leg(
                    .rail,
                    JourneyFixtures.oslo,
                    JourneyFixtures.bergen,
                    on: "2024-06-13",
                    departs: "2024-06-13T08:00",
                    arrives: "2024-06-13T14:30"
                ),
            ]),
            Journey(legs: [
                JourneyFixtures.leg(
                    .rail,
                    JourneyFixtures.oslo,
                    JourneyFixtures.stockholm,
                    on: "2024-06-13",
                    departs: "2024-06-13T16:00",
                    arrives: "2024-06-13T21:00"
                ),
                JourneyFixtures.leg(
                    .flight,
                    JourneyFixtures.stockholm,
                    JourneyFixtures.oslo,
                    on: "2024-06-20"
                ),
            ]),
        ])
        let stats = JourneyStatistics.compute(for: log)
        #expect(stats.minutesByMode == [.rail: 690])
        #expect(stats.durationInput.exclusions[.timesUnavailable] == 1)
        #expect(try stats.busiestDay == BusiestDay(
            day: #require(CalendarDate(iso: "2024-06-13")),
            legs: 2
        ))
        #expect(stats.bordersCrossedOverland == 1)
        #expect(stats.countriesOverland == ["NO", "SE"])
        #expect(stats.mostVariedJourney?.legs.count == 2)
        #expect(stats.multiLegJourneys == 1)
    }
}

@Suite("Rail")
struct RailStatisticsTests {
    @Test("Operators, classes, overnight legs and catalogue routes are counted")
    func rail() {
        var sleeper = JourneyFixtures.leg(
            .rail,
            JourneyFixtures.oslo,
            JourneyFixtures.stockholm,
            on: "2024-06-01",
            operatorName: "SJ",
            travelClass: "Sleeper"
        )
        sleeper.routeID = 1
        let day = JourneyFixtures.leg(
            .rail,
            JourneyFixtures.oslo,
            JourneyFixtures.bergen,
            on: "2024-06-05",
            operatorName: "Vy",
            travelClass: "Standard"
        )
        let route = RouteInfo(id: 1, name: "Bergen Line", mode: .rail, highestPointM: 1237)
        let stats = RailStatistics.compute(
            for: TravelLog(journeys: [Journey(legs: [sleeper]), Journey(legs: [day])]),
            routes: [route]
        )
        #expect(stats.legCount == 2)
        #expect(stats.operators == ["SJ", "Vy"])
        #expect(stats.classes == ["Sleeper", "Standard"])
        #expect(stats.overnightLegs == 1)
        #expect(stats.namedServices == ["Bergen Line"])
        #expect(stats.highestPointM == 1237)
        #expect(stats.bordersCrossed == 1)
        #expect(stats.countries == ["NO", "SE"])
        #expect(stats.stations.count == 3)
    }
}

@Suite("Punctuality")
struct PunctualityTests {
    /// Delays: Vy 10 and 20 (mean 15), SAS 0 and 2 (mean 1), Norse 60 (one leg, so not
    /// ranked). Overall (10 + 20 + 0 + 2 + 60) / 5 = 18.4. On time (≤ 15 min): 10, 0, 2
    /// = 3 of 5.
    @Test("Delays average by operator, and only operators with enough legs are ranked")
    func punctuality() {
        func timed(_ operatorName: String, late minutes: Int) -> JourneyLeg {
            let actual = String(format: "2024-06-01T%02d:%02d", 12 + minutes / 60, minutes % 60)
            return JourneyFixtures.leg(
                .flight,
                JourneyFixtures.oslo,
                JourneyFixtures.bergen,
                on: "2024-06-01",
                arrives: "2024-06-01T12:00",
                actualArrival: actual,
                operatorName: operatorName
            )
        }
        let legs = [
            timed("Vy", late: 10), timed("Vy", late: 20), timed("SAS", late: 0), timed(
                "SAS",
                late: 2
            ),
            timed("Norse", late: 60),
            JourneyFixtures.leg(
                .flight,
                JourneyFixtures.oslo,
                JourneyFixtures.bergen,
                on: "2024-06-02"
            ),
        ]
        let stats = PunctualityStatistics.compute(for: TravelLog(journeys: [Journey(legs: legs)]))
        #expect(stats.averageDelayMinutes == 18.4)
        #expect(stats.onTimeShare == 0.6)
        #expect(stats.mostPunctualOperator?.name == "SAS")
        #expect(stats.leastPunctualOperator?.name == "Vy")
        #expect(stats.worstDelayMinutes == 60)
        #expect(stats.input.exclusions[.timesUnavailable] == 1)
    }
}

@Suite("Carbon")
struct CarbonStatisticsTests {
    static let factors = EmissionFactorTable(
        factors: [
            EmissionFactor(
                mode: .flight,
                kgCO2ePerKm: 0.14253,
                basis: .passenger,
                label: "flight",
                year: 2025
            ),
            EmissionFactor(
                mode: .rail,
                kgCO2ePerKm: 0.03546,
                basis: .passenger,
                label: "rail",
                year: 2025
            ),
            EmissionFactor(
                mode: .roadTrip,
                kgCO2ePerKm: 0.16725,
                basis: .vehicle,
                label: "car",
                year: 2025
            ),
        ],
        sourceName: "DESNZ"
    )

    /// Two points one degree apart on the Equator are 111.195 km apart on the great
    /// circle (2π × 6,371.0088 / 360). A 150 km rail leg between them emits
    /// 150 × 0.03546 = 5.319 kg; flying the 111.195 km would emit 15.8486 kg, so the
    /// train saved 10.5296 kg. A 1,000 km flight emits 142.53 kg.
    @Test("Each leg is distance times its factor, and ground legs are compared with flying")
    func carbon() throws {
        let west = JourneyFixtures.place("West", "EC", latitude: 0, longitude: 0, zone: nil)
        let east = JourneyFixtures.place("East", "EC", latitude: 0, longitude: 1, zone: nil)
        let rail = JourneyFixtures.leg(.rail, west, east, on: "2024-03-01", distanceKm: 150)
        let flight = JourneyFixtures.leg(.flight, west, east, on: "2023-03-01", distanceKm: 1000)
        let gondola = JourneyFixtures.leg(
            .cableAndMountain,
            west,
            east,
            on: "2024-03-02",
            distanceKm: 2
        )
        let trip = UUID()
        let stats = CarbonStatistics.compute(
            for: TravelLog(journeys: [Journey(legs: [rail, flight, gondola], tripID: trip)]),
            factors: Self.factors
        )
        #expect(try abs(#require(stats.kgByLeg[rail.id]) - 5.319) < 1e-9)
        #expect(try abs(#require(stats.kgByLeg[flight.id]) - 142.53) < 1e-9)
        #expect(abs(stats.totalKg - 147.849) < 1e-9)
        #expect(try abs(#require(stats.savedByLeg[rail.id]) - 10.5296) < 1e-3)
        #expect(stats.savedByLeg[flight.id] == nil)
        #expect(try abs(#require(stats.kgByYear[2024]) - 5.319) < 1e-9)
        #expect(try abs(#require(stats.kgByTrip[trip]) - 147.849) < 1e-9)
        #expect(stats.input.exclusions[.noEmissionFactor] == 1)
        #expect(stats.factorYear == 2025)
    }

    @Test("A road trip's factor is per vehicle, and is flagged as such")
    func vehicleBasis() {
        let west = JourneyFixtures.place("West", "EC", latitude: 0, longitude: 0, zone: nil)
        let east = JourneyFixtures.place("East", "EC", latitude: 0, longitude: 1, zone: nil)
        let drive = JourneyFixtures.leg(.roadTrip, west, east, on: "2024-03-01", distanceKm: 100)
        let stats = CarbonStatistics.compute(
            for: TravelLog(journeys: [Journey(legs: [drive])]),
            factors: Self.factors
        )
        #expect(stats.vehicleBasisLegs == 1)
        #expect(abs(stats.totalKg - 16.725) < 1e-9)
    }
}

@Suite("Collections and wishlist")
struct CollectionTests {
    static let route = PlaceReference(id: .database(.route, 1), kind: .route, name: "Bergen Line")
    static let collection = CollectionDefinition(
        id: "test",
        name: "Test",
        members: [Fixtures.rome, Fixtures.tokyo, route]
    )

    /// The Colosseum ticks off Rome (R-MODEL-6). Tokyo passed through does not count
    /// (R-CALC-1). Riding route 1 ticks off the route.
    @Test("Members are ticked off through the implication chain and by riding a route")
    func progress() throws {
        var ride = Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen)
        ride.routeID = 1
        ride.date = .day(V1Fixtures.day("2024-06-01"))
        let log = TravelLog(
            visits: [
                Fixtures.visit(Fixtures.colosseum, .dayTrip, .day(V1Fixtures.day("2024-05-01"))),
                Fixtures.visit(Fixtures.tokyo, .passedThrough, .day(V1Fixtures.day("2024-04-01"))),
            ],
            journeys: [Journey(legs: [ride])]
        )
        let progress = try #require(CollectionProgress.compute(
            collections: [Self.collection],
            log: log
        ).first)
        #expect(progress.visitedCount == 2)
        #expect(progress.total == 3)
        #expect(!progress.isComplete)
        #expect(progress.members.first { $0.place.name == "Rome" }?.firstVisited == V1Fixtures
            .day("2024-05-01"))

        var complete = log
        complete.visits.append(Fixtures.visit(
            Fixtures.tokyo,
            .stayed,
            .day(V1Fixtures.day("2024-08-01"))
        ))
        let done = try #require(CollectionProgress.compute(
            collections: [Self.collection],
            log: complete
        ).first)
        #expect(done.isComplete)
        #expect(done.completedOn == V1Fixtures.day("2024-08-01"))
    }

    /// R-WISH-4: nothing is stored, so logging the visit is all it takes.
    @Test("A wishlist entry is ticked off by logging a visit that covers it")
    func wishlist() {
        let wish = WishlistItem(place: Fixtures.rome)
        let before = WishlistStatus.compute(log: TravelLog(wishlist: [wish]))
        #expect(before.first?.isVisited == false)
        let after = WishlistStatus.compute(log: TravelLog(
            visits: [Fixtures.visit(Fixtures.colosseum)],
            wishlist: [wish]
        ))
        #expect(after.first?.isVisited == true)
    }

    /// A wishlisted route records the station it starts from, so it can be drawn; that
    /// station is not the wish. Visiting Oslo must not tick off the Bergen Line, pin a
    /// wish on Oslo, or name the entry "Oslo".
    @Test("A wishlisted route is ticked off by riding it, not by visiting where it starts")
    func wishlistedRoute() {
        let wish = WishlistItem(place: Fixtures.oslo, routeID: 1, routeName: "Bergen Line")
        #expect(wish.title == "Bergen Line")
        #expect(wish.wishedPlace == nil)

        let visitedStart = WishlistStatus.compute(log: TravelLog(
            visits: [Fixtures.visit(Fixtures.oslo)],
            wishlist: [wish]
        ))
        #expect(visitedStart.first?.isVisited == false)

        var ride = Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen)
        ride.routeID = 1
        let rode = WishlistStatus.compute(log: TravelLog(
            journeys: [Journey(legs: [ride])],
            wishlist: [wish]
        ))
        #expect(rode.first?.isVisited == true)
    }
}

@Suite("Achievements")
struct AchievementTests {
    static func definition(
        _ id: String,
        _ rule: AchievementRule?,
        threshold: Double? = nil,
        parameter: String? = nil
    ) -> AchievementDefinition {
        AchievementDefinition(
            id: id,
            name: id,
            description: id,
            rule: rule,
            threshold: threshold,
            parameter: parameter
        )
    }

    /// Norway on 5 January, Italy on 1 March: the second country arrives on 1 March.
    /// Japan is undated and adds to the count but not to the date.
    @Test("A count achievement records the day its threshold was crossed")
    func countries() throws {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo, .stayed, .day(V1Fixtures.day("2024-01-05"))),
            Fixtures.visit(Fixtures.rome, .stayed, .day(V1Fixtures.day("2024-03-01"))),
            Fixtures.visit(Fixtures.tokyo, .stayed, .unknown),
        ])
        let statuses = AchievementEngine.evaluate(
            [
                Self.definition("two", .countries, threshold: 2),
                Self.definition("four", .countries, threshold: 4),
            ],
            log: log
        )
        let two = try #require(statuses.first { $0.id == "two" })
        #expect(two.isEarned)
        #expect(two.earnedOn == V1Fixtures.day("2024-03-01"))
        let four = try #require(statuses.first { $0.id == "four" })
        #expect(!four.isEarned)
        #expect(four.current == 3)
        #expect(four.progress == 0.75)
    }

    @Test("An achievement with a rule this build does not know is skipped, not guessed")
    func unknownRule() {
        let statuses = AchievementEngine.evaluate([Self.definition("future", nil)], log: .empty)
        #expect(statuses.isEmpty)
    }

    @Test("Hemispheres and the polar circles are read from where the user has been")
    func latitudes() {
        let log = TravelLog(
            visits: [Fixtures.visit(Fixtures.longyearbyen)],
            journeys: [Journey(legs: [Fixtures.flight(Fixtures.osl, Fixtures.syd)])]
        )
        let statuses = AchievementEngine.evaluate(
            [
                Self.definition("equator", .crossedEquator),
                Self.definition("arctic", .arcticCircle),
                Self.definition("antarctic", .antarcticCircle),
            ],
            log: log
        )
        #expect(statuses.first { $0.id == "equator" }?.isEarned == true)
        #expect(statuses.first { $0.id == "arctic" }?.isEarned == true)
        #expect(statuses.first { $0.id == "antarctic" }?.isEarned == false)
    }

    /// Madrid's antipode is (−40.42, 176.30); Wellington (−41.29, 174.78) is about
    /// 1.44° of arc from it — roughly 160 km — well inside a 2,000 km threshold.
    @Test("Two nearly antipodal places earn the namesake achievement")
    func antipodes() throws {
        func city(_ name: String, _ latitude: Double, _ longitude: Double) -> PlaceReference {
            PlaceReference(
                id: .custom(UUID()),
                kind: .custom,
                name: name,
                coordinate: Coordinate(latitude: latitude, longitude: longitude),
                countryCode: "XX"
            )
        }
        let log = TravelLog(visits: [
            Fixtures.visit(city("Madrid", 40.4168, -3.7038)),
            Fixtures.visit(city("Wellington", -41.2865, 174.7762)),
        ])
        let status = try #require(
            AchievementEngine.evaluate(
                [Self.definition("antipodes", .antipodes, threshold: 2000)],
                log: log
            ).first
        )
        #expect(status.isEarned)
        #expect(status.current > 100 && status.current < 250)
    }

    @Test("Collection achievements read the collection's own progress")
    func collection() throws {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.rome, .stayed, .day(V1Fixtures.day("2024-02-01"))),
            Fixtures.visit(Fixtures.tokyo, .stayed, .day(V1Fixtures.day("2024-03-01"))),
        ])
        let definition = CollectionDefinition(
            id: "pair",
            name: "Pair",
            members: [Fixtures.rome, Fixtures.tokyo]
        )
        let progress = CollectionProgress.compute(collections: [definition], log: log)
        let status = try #require(
            AchievementEngine.evaluate(
                [Self.definition("pair", .collectionComplete, parameter: "pair")],
                log: log,
                collections: progress
            ).first
        )
        #expect(status.isEarned)
        #expect(status.earnedOn == V1Fixtures.day("2024-03-01"))
    }
}

@Suite("Year in review")
struct YearInReviewTests {
    @Test("A year's countries, and which of them were new that year")
    func review() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo, .stayed, .year(2023)),
            Fixtures.visit(Fixtures.bergen, .stayed, .day(V1Fixtures.day("2024-04-01"))),
            Fixtures.visit(Fixtures.rome, .stayed, .day(V1Fixtures.day("2024-05-01"))),
            Fixtures.visit(Fixtures.tokyo, .stayed, .unknown),
        ])
        let review = YearInReview.compute(year: 2024, log: log)
        #expect(review.countries == ["NO", "IT"])
        #expect(review.newCountries == ["IT"])
        #expect(review.places == 2)
        #expect(review.undatedRecords == 1)
        #expect(YearInReview.availableYears(in: log) == [2024, 2023])
    }
}
