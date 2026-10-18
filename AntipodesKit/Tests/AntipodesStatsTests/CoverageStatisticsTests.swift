import AntipodesCore
import AntipodesStats
import Foundation
import Testing

@Suite("Coverage statistics")
struct CoverageStatisticsTests {
    /// Hand-computed: Oslo (NO), Rome (IT), Tokyo (JP) → 3 countries, 2 continents
    /// (Europe, Asia), 3 regions, 3 cities.
    @Test("Counts countries, continents, regions and cities")
    func basicCoverage() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.rome),
            Fixtures.visit(Fixtures.tokyo),
        ])
        let coverage = CoverageStatistics.compute(for: log)

        #expect(coverage.countriesVisited == 3)
        #expect(coverage.continentsVisited == 2)
        #expect(coverage.continents == [.europe, .asia])
        #expect(coverage.regionsVisited == 3)
        #expect(coverage.citiesVisited == 3)
        #expect(coverage.input.isComplete)
        #expect(coverage.input.caveat == nil)
    }

    /// R-CALC-3: the Colosseum twice is one landmark and one city, not two of each.
    @Test("Unique places count once, however many times they were visited")
    func uniquePlaces() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.colosseum, .dayTrip, .year(2019)),
            Fixtures.visit(Fixtures.colosseum, .dayTrip, .year(2024)),
        ])
        let coverage = CoverageStatistics.compute(for: log)

        #expect(coverage.landmarksVisited == 1)
        #expect(coverage.countriesVisited == 1)
        // Both visits were usable; de-duplication is not exclusion.
        #expect(coverage.input.used == 2)
        #expect(coverage.input.isComplete)
    }

    /// R-MODEL-6: logging a landmark implies its city, region and country.
    @Test("A landmark implies its city, region and country")
    func hierarchyImplication() {
        let log = TravelLog(visits: [Fixtures.visit(Fixtures.colosseum)])
        let coverage = CoverageStatistics.compute(for: log)

        #expect(coverage.countryCodes == ["IT"])
        #expect(coverage.regionCodes == ["IT-62"])
        #expect(coverage.cityIDs == [12])
        #expect(coverage.landmarksVisited == 1)
    }

    /// R-CALC-1 and M1 acceptance criterion 5.
    @Test("Passed through and layovers are excluded by default, and counted when asked")
    func visitTypeRules() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo, .stayed),
            Fixtures.visit(Fixtures.rome, .passedThrough),
            Fixtures.visit(Fixtures.tokyo, .layover),
        ])

        let strict = CoverageStatistics.compute(for: log, rules: .default)
        #expect(strict.countriesVisited == 1)
        #expect(strict.input.used == 1)
        #expect(strict.input.exclusions[.visitTypeNotCounted] == 2)
        #expect(strict.input.caveat != nil)

        let inclusive = CoverageStatistics.compute(
            for: log,
            rules: CountingRules(includePassedThrough: true, includeLayovers: true)
        )
        #expect(inclusive.countriesVisited == 3)
        #expect(inclusive.input.isComplete)
    }

    /// 3 of 193 UN members is 1.554%.
    @Test("Share of the world uses the configured denominator")
    func worldFraction() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.rome),
            Fixtures.visit(Fixtures.tokyo),
        ])
        let coverage = CoverageStatistics.compute(for: log)
        #expect(abs(coverage.worldFraction - 3.0 / 193.0) < 1e-12)

        let wider = CoverageStatistics.compute(
            for: log,
            rules: CountingRules(worldCountryCount: 250)
        )
        #expect(abs(wider.worldFraction - 3.0 / 250.0) < 1e-12)
    }

    @Test("Share of the world never exceeds 100%")
    func worldFractionCaps() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.rome),
        ])
        let coverage = CoverageStatistics.compute(
            for: log,
            rules: CountingRules(worldCountryCount: 1)
        )
        #expect(coverage.worldFraction == 1)
    }

    /// A visit with no country cannot be placed, and must be reported rather than
    /// quietly dropped (R-CALC-5).
    @Test("A place with no country is excluded and named in the caveat")
    func missingCountry() {
        let orphan = PlaceReference(
            id: .custom(UUID()),
            kind: .custom,
            name: "Somewhere at sea",
            coordinate: Coordinate(latitude: 0, longitude: -30)
        )
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(orphan),
        ])
        let coverage = CoverageStatistics.compute(for: log)

        #expect(coverage.countriesVisited == 1)
        #expect(coverage.input.exclusions[.missingCountry] == 1)
        #expect(coverage.input.used == 1)
        #expect(coverage.input.considered == 2)
        let caveat = coverage.input.caveat
        #expect(caveat?.contains("1 of 2") == true)
        #expect(caveat?.contains("no country resolved") == true)
    }

    @Test("An empty log reports zeros and is complete, not broken")
    func emptyLog() {
        let coverage = CoverageStatistics.compute(for: .empty)
        #expect(coverage.countriesVisited == 0)
        #expect(coverage.worldFraction == 0)
        #expect(coverage.input.isComplete)
        #expect(coverage.input.completeness == 1)
        #expect(coverage.input.caveat == nil)
    }

    @Test("All seven continents is recognised only at seven")
    func sevenContinents() {
        var visits = [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.tokyo),
        ]
        #expect(!CoverageStatistics.compute(
            for: TravelLog(visits: visits)
        ).hasVisitedAllSevenContinents)

        let remaining: [(String, String, Continent)] = [
            ("EG", "Egypt", .africa),
            ("US", "United States", .northAmerica),
            ("BR", "Brazil", .southAmerica),
            ("AU", "Australia", .oceania),
            ("AQ", "Antarctica", .antarctica),
        ]
        for (index, entry) in remaining.enumerated() {
            visits.append(Fixtures.visit(
                Fixtures.country(entry.0, entry.1, entry.2, id: Int64(100 + index))
            ))
        }

        let coverage = CoverageStatistics.compute(for: TravelLog(visits: visits))
        #expect(coverage.continentsVisited == 7)
        #expect(coverage.hasVisitedAllSevenContinents)
        #expect(coverage.continentFraction == 1)
    }

    @Test("Countries sort by display name")
    func countrySorting() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.tokyo),
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.rome),
        ])
        let names = CoverageStatistics.compute(for: log).countriesSortedByName.map(\.name)
        #expect(names == ["Italy", "Japan", "Norway"])
    }
}

@Suite("Extreme points")
struct ExtremePointsTests {
    /// Longitudes in this set: Oslo 10.75 °E, Longyearbyen 15.63 °E,
    /// Tokyo 139.65 °E, SYD 151.18 °E, JFK 73.78 °W. Latitudes: Longyearbyen 78.22 °N
    /// down to SYD 33.94 °S. So Longyearbyen is northernmost, SYD both southernmost
    /// and easternmost, and JFK westernmost.
    @Test("Finds the furthest point in each direction")
    func extremes() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.longyearbyen),
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.tokyo),
            Fixtures.visit(Fixtures.syd),
            Fixtures.visit(Fixtures.jfk),
        ])
        let extremes = ExtremePoints.compute(for: log)

        #expect(extremes.northernmost?.place.name == "Longyearbyen")
        #expect(extremes.southernmost?.place.name == "SYD")
        #expect(extremes.easternmost?.place.name == "SYD")
        #expect(extremes.westernmost?.place.name == "JFK")
    }

    /// Without SYD in the set, Tokyo is easternmost — so the comparison really is on
    /// longitude and not on the order places were logged.
    @Test("Easternmost compares longitude, not insertion order")
    func easternmostIsByLongitude() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.tokyo),
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(Fixtures.rome),
        ])
        let extremes = ExtremePoints.compute(for: log)
        #expect(extremes.easternmost?.place.name == "Tokyo")
        #expect(extremes.westernmost?.place.name == "Oslo")
    }

    @Test("A place with no coordinate is excluded and reported")
    func missingCoordinate() {
        let noCoordinate = PlaceReference(
            id: .database(.city, 99),
            kind: .city,
            name: "Unlocated",
            countryCode: "NO"
        )
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.oslo),
            Fixtures.visit(noCoordinate),
        ])
        let extremes = ExtremePoints.compute(for: log)

        #expect(extremes.input.exclusions[.missingCoordinate] == 1)
        #expect(extremes.northernmost?.place.name == "Oslo")
    }

    @Test("An empty log has no extremes rather than a default coordinate")
    func emptyLog() {
        let extremes = ExtremePoints.compute(for: .empty)
        #expect(extremes.northernmost == nil)
        #expect(extremes.southernmost == nil)
        #expect(extremes.nearestToAntipodeOfHome == nil)
    }

    /// Oslo's antipode sits in the South Pacific, so of this set Sydney is nearest to
    /// it — the stat the app is named after.
    @Test("Nearest to the antipode of home")
    func antipodeStat() {
        let log = TravelLog(visits: [
            Fixtures.visit(Fixtures.rome),
            Fixtures.visit(Fixtures.tokyo),
            Fixtures.visit(Fixtures.syd),
        ])
        let extremes = ExtremePoints.compute(
            for: log,
            rules: .default,
            home: Coordinate(latitude: 59.9139, longitude: 10.7522)
        )
        #expect(extremes.nearestToAntipodeOfHome?.place.name == "SYD")
    }
}
