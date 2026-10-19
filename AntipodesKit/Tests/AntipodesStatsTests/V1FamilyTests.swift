import AntipodesCore
import AntipodesStats
import Foundation
import Testing

/// Shared facts for the v1 families, written out by hand so every expected value below
/// can be checked on paper.
enum V1Fixtures {
    static func day(_ iso: String) -> CalendarDate {
        CalendarDate(iso: iso)!
    }

    static func landmark(_ name: String, id: Int64) -> PlaceReference {
        PlaceReference(
            id: .database(.landmark, id),
            kind: .landmark,
            name: name,
            coordinate: Coordinate(latitude: 41.9, longitude: 12.5),
            countryCode: "IT",
            countryName: "Italy",
            continent: .europe
        )
    }

    static let gazetteer = Gazetteer(
        places: [
            .database(.city, 10): PlaceFacts(population: 700_000, elevationM: 23, isCapital: true),
            .database(.city, 12): PlaceFacts(
                population: 2_800_000,
                elevationM: 20,
                isCapital: true
            ),
            .database(.city, 11): PlaceFacts(elevationM: 12),
            .database(.landmark, 20): PlaceFacts(
                yearBuilt: 80,
                isUNESCO: true,
                themes: ["ancient-history", "architecture"]
            ),
        ],
        countries: [
            "NO": CountryFacts(
                code: "NO",
                name: "Norway",
                continent: .europe,
                currencyCode: "NOK",
                languageCodes: ["no", "nb", "nn"],
                isUNMember: true
            ),
            "IT": CountryFacts(
                code: "IT",
                name: "Italy",
                continent: .europe,
                currencyCode: "EUR",
                languageCodes: ["it-IT", "de-IT"],
                isUNMember: true
            ),
            "JP": CountryFacts(
                code: "JP",
                name: "Japan",
                continent: .asia,
                currencyCode: "JPY",
                languageCodes: ["ja"],
                isUNMember: true
            ),
            "SJ": CountryFacts(
                code: "SJ",
                name: "Svalbard",
                continent: .europe,
                currencyCode: "NOK",
                languageCodes: ["no", "ru"]
            ),
        ],
        themes: [ThemeDefinition(id: "ancient-history", label: "Ancient history")]
    )
}

@Suite("Coverage against a chosen country list")
struct ListedCoverageTests {
    /// Q-4: Svalbard has its own ISO code but is not a UN member. Counting UN members,
    /// it must not raise "% of the world": 1 of 193, not 2 of 193.
    @Test("Only countries on the chosen list count towards % of the world")
    func listedCountries() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.longyearbyen),
        ])
        let un = CoverageStatistics.compute(
            for: log,
            rules: .default,
            gazetteer: V1Fixtures.gazetteer
        )
        #expect(un.countriesVisited == 2)
        #expect(un.listedCountriesVisited == 1)
        #expect(un.unlistedCountryCodes == ["SJ"])
        #expect(abs(un.worldFraction - 1.0 / 193.0) < 1e-12)

        let all = CoverageStatistics.compute(
            for: log,
            rules: CountingRules(countryList: .allCountriesAndTerritories, worldCountryCount: 252),
            gazetteer: V1Fixtures.gazetteer
        )
        #expect(all.listedCountriesVisited == 2)
    }

    @Test("Capitals and UNESCO sites come from the gazetteer, implied cities included")
    func capitalsAndUNESCO() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.colosseum),
            Fixtures.visit(Fixtures.bergen),
        ])
        let coverage = CoverageStatistics.compute(for: log, gazetteer: V1Fixtures.gazetteer)
        // The Colosseum implies Rome, a capital; Bergen is not one.
        #expect(coverage.capitalCityIDs == [12])
        #expect(coverage.unescoSitesVisited == 1)
        #expect(coverage.visitIDsByCountry["NO"]?.count == 1)
    }

    @Test("The first known day in each country is recorded")
    func firstDay() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo, .stayed, .day(V1Fixtures.day("2024-06-10"))),
            Fixtures.visit(Fixtures.bergen, .stayed, .month(year: 2019, month: 3)),
            Fixtures.visit(Fixtures.rome, .stayed, .unknown),
        ])
        let coverage = CoverageStatistics.compute(for: log)
        #expect(coverage.firstDayByCountry["NO"] == V1Fixtures.day("2019-03-01"))
        #expect(coverage.firstDayByCountry["IT"] == nil)
    }
}

@Suite("Place attributes")
struct PlaceAttributeTests {
    /// Hand-computed, reference year 2024: built 80 → 1,944 years; built −447 → 2,471
    /// years. Mean and median are both (1944 + 2471) / 2 = 2,207.5. The third landmark
    /// has no year and is excluded, not counted as zero.
    @Test("Landmark age averages unique landmarks with a known year, and says how many")
    func landmarkAge() {
        let parthenon = V1Fixtures.landmark("Parthenon", id: 21)
        let unknown = V1Fixtures.landmark("Somewhere", id: 22)
        var gazetteer = V1Fixtures.gazetteer
        gazetteer.places[parthenon.id] = PlaceFacts(yearBuilt: -447)
        gazetteer.places[unknown.id] = PlaceFacts()

        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.colosseum),
            Fixtures.visit(Fixtures.colosseum), // twice: still one landmark (R-CALC-3)
            Fixtures.visit(parthenon),
            Fixtures.visit(unknown),
        ])
        let stats = PlaceAttributeStatistics.compute(
            for: log,
            gazetteer: gazetteer,
            referenceYear: 2024
        )
        #expect(stats.averageLandmarkAgeYears == 2207.5)
        #expect(stats.medianLandmarkAgeYears == 2207.5)
        #expect(stats.oldestLandmark?.place.name == "Parthenon")
        #expect(stats.oldestLandmark?.value == -447)
        #expect(stats.newestLandmark?.place.name == "Colosseum")
        #expect(stats.landmarkAgeInput.used == 2)
        #expect(stats.landmarkAgeInput.exclusions[.attributeUnknown] == 1)
        #expect(stats.landmarkAgeInput.caveat(counting: "landmarks")?
            .contains("2 of 3 landmarks") == true)
    }

    /// Cities: Oslo 700,000 and Rome 2,800,000 → mean 1,750,000. Rome is reached through
    /// the Colosseum as well as directly and still counts once. Bergen has no population
    /// and is excluded. Elevation: Oslo 23, Rome 20, Bergen 12 → mean 55 / 3.
    @Test("City size and elevation are averaged over unique cities")
    func citySizeAndElevation() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.rome),
            Fixtures.visit(Fixtures.colosseum),
            Fixtures.visit(Fixtures.bergen),
        ])
        let stats = PlaceAttributeStatistics.compute(
            for: log,
            gazetteer: V1Fixtures.gazetteer,
            referenceYear: 2024
        )
        #expect(stats.averageCityPopulation == 1_750_000)
        #expect(stats.cityPopulationInput.used == 2)
        #expect(stats.cityPopulationInput.excludedCount == 1)
        #expect(stats.largestCity?.place.name == "Rome")
        #expect(abs((stats.averageElevationM ?? 0) - 55.0 / 3.0) < 1e-9)
        #expect(stats.highestPlace?.place.name == "Oslo")
        #expect(stats.lowestPlace?.place.name == "Bergen")
    }

    /// GeoNames writes "it-IT"; the main language is "it". Norway and Svalbard share NOK.
    @Test("Languages and currencies come from the visited countries")
    func languagesAndCurrencies() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.longyearbyen),
            Fixtures.visit(Fixtures.rome),
        ])
        let stats = PlaceAttributeStatistics.compute(
            for: log,
            gazetteer: V1Fixtures.gazetteer,
            referenceYear: 2024
        )
        #expect(stats.languageCodes == ["no", "it"])
        #expect(stats.currencyCodes == ["NOK", "EUR"])
    }

    @Test("An empty log has no averages and nothing excluded")
    func empty() {
        let stats = PlaceAttributeStatistics.compute(
            for: .empty,
            gazetteer: .empty,
            referenceYear: 2024
        )
        #expect(stats.averageLandmarkAgeYears == nil)
        #expect(stats.averageCityPopulation == nil)
        #expect(stats.landmarkAgeInput.isComplete)
    }
}

@Suite("Time and patterns")
struct TimeStatisticsTests {
    static let today = V1Fixtures.day("2024-10-20")

    static func log(tripA: UUID, tripB: UUID) -> TravelLog {
        TravelLog(
            trips: [Trip(id: tripA, name: "Summer"), Trip(id: tripB, name: "Bergen")],
            visits: [
                Fixtures.visit(
                    Fixtures.oslo,
                    .stayed,
                    .span(V1Fixtures.day("2024-06-10"), V1Fixtures.day("2024-06-12")),
                    trip: tripA
                ),
                Fixtures.visit(
                    Fixtures.rome,
                    .dayTrip,
                    .day(V1Fixtures.day("2024-07-01")),
                    trip: tripA
                ),
                Fixtures.visit(Fixtures.rome, .dayTrip, .day(V1Fixtures.day("2023-05-05"))),
                Fixtures.visit(Fixtures.bergen, .stayed, .month(year: 2024, month: 6), trip: tripB),
                Fixtures.visit(Fixtures.tokyo, .stayed, .unknown),
            ],
            journeys: [
                Journey(legs: [
                    JourneyLeg(
                        mode: .flight,
                        origin: Fixtures.osl,
                        destination: Fixtures.lhr,
                        date: .day(V1Fixtures.day("2024-06-12"))
                    ),
                ]),
            ]
        )
    }

    /// Home is Bergen, so the Bergen visit is not "away". Days: 10, 11, 12 June from the
    /// Oslo range, 12 June again from the flight (counted once), 1 July in Rome — four
    /// days in 2024 — and 5 May 2023 in Rome. Tokyo has no date and is excluded.
    @Test("Days away count each day once and leave home out")
    func daysAway() {
        let stats = TimeStatistics.compute(
            for: Self.log(tripA: UUID(), tripB: UUID()),
            home: Fixtures.bergen,
            today: Self.today
        )
        #expect(stats.daysAwayByYear == [2024: 4, 2023: 1])
        #expect(stats.totalDaysAway == 5)
        #expect(stats.daysAwayInput.exclusions[.unknownDate] == 1)
    }

    /// Without a home the Bergen month cannot place days: it is excluded as too
    /// imprecise rather than counted as thirty days.
    @Test("A month-only visit is excluded from days away, and says why")
    func monthPrecision() {
        let stats = TimeStatistics.compute(
            for: Self.log(tripA: UUID(), tripB: UUID()),
            today: Self.today
        )
        #expect(stats.daysAwayInput.exclusions[.datePrecisionTooLow] == 1)
        #expect(stats.daysAwayByYear[2024] == 4)
    }

    /// Trip A spans 10 June to 1 July 2024: 22 days. Trip B is dated only to a month,
    /// so it counts as a 2024 trip but has no length.
    @Test("Trips are counted by start year and measured only when both ends are exact")
    func trips() {
        let tripA = UUID()
        let stats = TimeStatistics.compute(
            for: Self.log(tripA: tripA, tripB: UUID()),
            today: Self.today
        )
        #expect(stats.tripsByYear == [2024: 2])
        #expect(stats.tripSpans.count == 1)
        #expect(stats.tripSpans.first?.tripID == tripA)
        #expect(stats.tripSpans.first?.days == 22)
        #expect(stats.averageTripDays == 22)
    }

    /// Months: Oslo June, Rome July, Rome May (2023), Bergen June. Tokyo has none.
    @Test("Seasonality counts visits per month and finds the busiest one")
    func seasonality() {
        let stats = TimeStatistics.compute(
            for: Self.log(tripA: UUID(), tripB: UUID()),
            today: Self.today
        )
        #expect(stats.visitsByMonth == [6: 2, 7: 1, 5: 1])
        #expect(stats.busiestMonth == BusiestMonth(year: 2024, month: 6, visits: 2))
        #expect(stats.monthInput.exclusions[.unknownDate] == 1)
        #expect(stats.visitsByYear == [2024: 3, 2023: 1])
        #expect(stats.newCountriesByYear == [2023: ["IT"], 2024: ["NO"]])
    }

    @Test("Repeat visits are places with more than one visit")
    func repeats() {
        let stats = TimeStatistics.compute(
            for: Self.log(tripA: UUID(), tripB: UUID()),
            today: Self.today
        )
        #expect(stats.repeatVisits.map(\.place.name) == ["Rome"])
        #expect(stats.repeatVisits.first?.visitCount == 2)
    }

    /// Norway was last visited on the last day of June 2024 (the Bergen month's latest
    /// possible day): 30 June → 20 October is 112 days. Italy, 1 July: 111 days.
    @Test("Country gaps run from the last possible day of the last visit")
    func gaps() {
        let stats = TimeStatistics.compute(
            for: Self.log(tripA: UUID(), tripB: UUID()),
            today: Self.today
        )
        #expect(stats.countryGaps.map(\.countryCode) == ["NO", "IT"])
        #expect(stats.countryGaps.map(\.daysSince) == [112, 111])
    }

    @Test("On this day matches exact days and spanning ranges in earlier years")
    func onThisDay() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo, .stayed, .day(V1Fixtures.day("2019-10-20"))),
            Fixtures.visit(
                Fixtures.rome,
                .stayed,
                .span(V1Fixtures.day("2022-10-18"), V1Fixtures.day("2022-10-25"))
            ),
            Fixtures.visit(Fixtures.tokyo, .stayed, .month(year: 2021, month: 10)),
            Fixtures.visit(Fixtures.bergen, .stayed, .day(V1Fixtures.day("2024-10-20"))),
        ])
        let entries = TimeStatistics.compute(for: log, today: Self.today).onThisDay
        #expect(entries.map(\.year) == [2022, 2019])
        #expect(entries.map(\.yearsAgo) == [2, 5])
    }
}

@Suite("Themes and travel personality")
struct ThemeStatisticsTests {
    static func themedLog(_ themes: [[String]]) -> (TravelLog, Gazetteer) {
        var gazetteer = Gazetteer()
        var visits: [Visit] = []
        for (index, tags) in themes.enumerated() {
            let place = V1Fixtures.landmark("L\(index)", id: Int64(100 + index))
            gazetteer.places[place.id] = PlaceFacts(themes: tags)
            visits.append(Fixtures.visit(place))
        }
        return (TravelLog(visits: visits), gazetteer)
    }

    /// Weights: ancient 0.5 + 1 = 1.5, archaeology 0.5, medieval 0.5, architecture 0.5,
    /// nature 1, military 1 → total 5. The historian group holds 1.5 + 0.5 + 0.5 + 1 =
    /// 3.5, a share of 0.7, past its 0.4 threshold.
    @Test("A history-heavy mix reads as a Historian, with the shares behind it")
    func historian() throws {
        let (log, gazetteer) = Self.themedLog([
            ["ancient-history", "archaeology"],
            ["ancient-history"],
            ["medieval-history", "architecture"],
            ["nature"],
            ["military-history"],
        ])
        let stats = ThemeStatistics.compute(for: log, gazetteer: gazetteer)
        #expect(stats.landmarkCount == 5)
        #expect(stats.shares.first?.theme == "ancient-history")
        #expect(stats.shares.first?.share == 0.3)
        let personality = try #require(stats.personality)
        #expect(personality.archetype == .historian)
        let historian = try #require(personality.scores.first { $0.archetype == .historian })
        #expect(abs(historian.share - 0.7) < 1e-12)
        #expect(personality.scores.first?.archetype == .historian)
    }

    @Test("Fewer than five themed landmarks is too thin to call")
    func tooFew() {
        let (log, gazetteer) = Self.themedLog([["nature"], ["nature"], ["nature"], ["nature"]])
        #expect(ThemeStatistics.compute(for: log, gazetteer: gazetteer).personality == nil)
    }

    /// Five groups at 0.2 each: no group reaches its threshold (historian, trailblazer
    /// and aesthete need 0.4, pilgrim 0.3, futurist 0.35).
    @Test("A balanced mix is a Wanderer")
    func wanderer() {
        let (log, gazetteer) = Self.themedLog([
            ["nature"], ["art-and-museums"], ["religious-sites"], ["modern-architecture"],
            ["ancient-history"],
        ])
        #expect(ThemeStatistics.compute(for: log, gazetteer: gazetteer).personality?
            .archetype == .wanderer)
    }

    @Test("Landmarks are bucketed into historical eras by year built")
    func eras() {
        let years: [Int?] = [80, -447, 1163, 1889, nil]
        var gazetteer = Gazetteer()
        var visits: [Visit] = []
        for (index, year) in years.enumerated() {
            let place = V1Fixtures.landmark("L\(index)", id: Int64(200 + index))
            gazetteer.places[place.id] = PlaceFacts(yearBuilt: year, themes: ["architecture"])
            visits.append(Fixtures.visit(place))
        }
        let stats = ThemeStatistics.compute(for: TravelLog(visits: visits), gazetteer: gazetteer)
        #expect(stats.landmarksByEra == [.ancient: 2, .medieval: 1, .industrial: 1])
        #expect(stats.eraInput.exclusions[.attributeUnknown] == 1)
    }
}
