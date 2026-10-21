import AntipodesCore
import AntipodesStats
import Foundation
import Testing

@Suite("Distance statistics")
struct DistanceStatisticsTests {
    /// OSL→JFK is about 5,920 km and LHR→SYD about 16,990 km, so the total is about
    /// 22,910 km. Checked at 1% because the reference figures are themselves rounded.
    @Test("Totals distance across legs and splits it by mode")
    func totals() {
        let log = TravelLog(journeys: [
            Journey(legs: [Fixtures.flight(Fixtures.osl, Fixtures.jfk)]),
            Journey(legs: [Fixtures.flight(Fixtures.lhr, Fixtures.syd)]),
        ])
        let distance = DistanceStatistics.compute(for: log)

        #expect(abs(distance.totalKm - 22910) / 22910 < 0.01)
        #expect(distance.legCount == 2)
        #expect(distance.legCountByMode[.flight] == 2)
        #expect(distance.kilometresByMode.count == 1)
        #expect(distance.input.isComplete)
    }

    /// Once round the Equator is 40,075.017 km (WGS-84), the same figure the "Round the
    /// world" badge is earned at, so 80,150.034 km is exactly twice round.
    @Test("Times round the Earth divides by the equatorial circumference")
    func timesRoundTheEarth() {
        let leg = JourneyLeg(
            mode: .flight,
            origin: Fixtures.osl,
            destination: Fixtures.jfk,
            distanceKmOverride: 80150.034
        )
        let distance = DistanceStatistics.compute(for: TravelLog(journeys: [
            Journey(legs: [leg]),
        ]))
        #expect(abs(distance.timesRoundTheEarth - 2) < 1e-9)
    }

    /// R-PATH-5: a real stored path wins over the straight line, and the user's own
    /// figure wins over both.
    @Test("Distance source precedence: override, then stored path, then great circle")
    func distancePrecedence() {
        let greatCircleOnly = Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen)
        #expect(greatCircleOnly.distanceSource == .greatCircleApproximate)

        // The Bergen Line is 496 km of track; the straight line is about 304 km.
        let withPath = Fixtures.railLeg(
            Fixtures.oslo,
            Fixtures.bergen,
            storedPathLengthKm: 496
        )
        #expect(withPath.distanceSource == .storedPath)
        #expect(withPath.distanceKm == 496)

        var overridden = withPath
        overridden.distanceKmOverride = 500
        #expect(overridden.distanceSource == .userOverride)
        #expect(overridden.distanceKm == 500)
    }

    /// A flight's great circle *is* its path, so it is exact, not approximate
    /// (R-PATH-4).
    @Test("A flight's great circle is exact; a rail leg's is approximate")
    func flightVersusGroundPaths() {
        #expect(Fixtures.flight(Fixtures.osl, Fixtures.jfk).distanceSource
            == .greatCircleExact)
        #expect(!Fixtures.flight(Fixtures.osl, Fixtures.jfk).distanceSource.isApproximate)
        #expect(Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen).distanceSource
            .isApproximate)
    }

    /// R-PATH-3: an approximated total has to be visible, not folded into the number.
    @Test("Approximate legs are counted and their share reported")
    func approximateReporting() {
        let log = TravelLog(journeys: [
            Journey(legs: [Fixtures.flight(Fixtures.osl, Fixtures.jfk)]),
            Journey(legs: [Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen)]),
        ])
        let distance = DistanceStatistics.compute(for: log)

        #expect(distance.approximateLegCount == 1)
        #expect(distance.approximateKm > 0)
        #expect(distance.approximateKm < distance.totalKm)
        // The rail leg is a small fraction of a transatlantic flight.
        #expect(distance.approximateFraction < 0.1)
    }

    /// A leg between two places with no coordinates has no distance at all, and must
    /// be excluded with a reason rather than counted as zero.
    @Test("A leg with no coordinates is excluded, not counted as zero")
    func unavailableDistance() {
        let nowhere = PlaceReference(id: .custom(UUID()), kind: .custom, name: "Nowhere")
        let log = TravelLog(journeys: [
            Journey(legs: [Fixtures.flight(Fixtures.osl, Fixtures.jfk)]),
            Journey(legs: [JourneyLeg(mode: .rail, origin: nowhere, destination: nowhere)]),
        ])
        let distance = DistanceStatistics.compute(for: log)

        #expect(distance.legCount == 1)
        #expect(distance.input.exclusions[.distanceUnavailable] == 1)
        #expect(distance.input.caveat?.contains("no distance available") == true)
    }

    /// Q-15: a daily tram ride would otherwise swamp the totals.
    @Test("Commutes are excluded by default and included when asked")
    func commuteRules() {
        let log = TravelLog(journeys: [
            Journey(legs: [Fixtures.flight(Fixtures.osl, Fixtures.jfk)]),
            Journey(legs: [
                Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen, purpose: .commute),
            ]),
        ])

        let excluded = DistanceStatistics.compute(for: log)
        #expect(excluded.legCount == 1)
        #expect(excluded.input.exclusions[.commuteExcluded] == 1)
        #expect(excluded.kilometresByMode[.rail] == nil)

        let included = DistanceStatistics.compute(
            for: log,
            rules: CountingRules(includeCommutes: true)
        )
        #expect(included.legCount == 2)
        #expect(included.kilometresByMode[.rail] != nil)
    }

    /// LHR→SYD is the longest leg, but it is one leg; OSL→LHR→JFK is the longest
    /// journey made of more than one.
    @Test("Finds the longest leg and the longest multi-leg journey")
    func longest() {
        let shortJourney = Journey(legs: [Fixtures.flight(Fixtures.osl, Fixtures.lhr)])
        let longLeg = Journey(legs: [Fixtures.flight(Fixtures.lhr, Fixtures.syd)])
        let multiLeg = Journey(legs: [
            Fixtures.flight(Fixtures.osl, Fixtures.lhr),
            Fixtures.flight(Fixtures.lhr, Fixtures.jfk),
        ])

        let distance = DistanceStatistics.compute(
            for: TravelLog(journeys: [shortJourney, longLeg, multiLeg])
        )
        #expect(distance.longestLeg?.destination.name == "SYD")
        #expect(distance.longestJourney?.id == multiLeg.id)
    }

    @Test("Modes sort by distance, descending")
    func modeOrdering() {
        let log = TravelLog(journeys: [
            Journey(legs: [Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen)]),
            Journey(legs: [Fixtures.flight(Fixtures.lhr, Fixtures.syd)]),
        ])
        let modes = DistanceStatistics.compute(for: log).modesSortedByDistance.map(\.mode)
        #expect(modes == [.flight, .rail])
    }

    @Test("An empty log totals zero and is complete")
    func emptyLog() {
        let distance = DistanceStatistics.compute(for: .empty)
        #expect(distance.totalKm == 0)
        #expect(distance.timesRoundTheEarth == 0)
        #expect(distance.approximateFraction == 0)
        #expect(distance.longestLeg == nil)
        #expect(distance.input.isComplete)
    }
}

@Suite("Flight statistics")
struct FlightStatisticsTests {
    @Test("Counts flights, airports, airlines and aircraft, ignoring other modes")
    func flightsOnly() {
        let log = TravelLog(journeys: [
            Journey(legs: [
                Fixtures.flight(Fixtures.osl, Fixtures.lhr, airline: "SK", aircraft: "A320neo"),
                Fixtures.flight(Fixtures.lhr, Fixtures.jfk, airline: "BA", aircraft: "B777"),
            ]),
            Journey(legs: [Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen)]),
        ])
        let flights = FlightStatistics.compute(for: log)

        #expect(flights.flightCount == 2)
        #expect(flights.airportsVisited == 3) // OSL, LHR, JFK — LHR counted once
        #expect(flights.airlineNames == ["SK", "BA"])
        #expect(flights.aircraftTypes == ["A320neo", "B777"])
        #expect(flights.longestFlight?.destination.name == "JFK")
    }

    /// OSL→LHR is about 1,160 km and LHR→JFK about 5,540 km, averaging about 3,350 km.
    @Test("Average flight distance")
    func averageDistance() {
        let log = TravelLog(journeys: [
            Journey(legs: [
                Fixtures.flight(Fixtures.osl, Fixtures.lhr),
                Fixtures.flight(Fixtures.lhr, Fixtures.jfk),
            ]),
        ])
        let flights = FlightStatistics.compute(for: log)
        #expect(abs(flights.averageFlightKm - 3350) / 3350 < 0.02)
    }

    @Test("No flights means zero, not a division by zero")
    func noFlights() {
        let log = TravelLog(journeys: [
            Journey(legs: [Fixtures.railLeg(Fixtures.oslo, Fixtures.bergen)]),
        ])
        let flights = FlightStatistics.compute(for: log)
        #expect(flights.flightCount == 0)
        #expect(flights.averageFlightKm == 0)
    }
}

@Suite("Statistics engine")
struct StatisticsEngineTests {
    @Test("Headlines are present and carry their caveats")
    func headlines() {
        let log = TravelLog(
            visits: [
                Fixtures.visit(Fixtures.oslo),
                Fixtures.visit(Fixtures.rome, .layover),
            ],
            journeys: [Journey(legs: [Fixtures.flight(Fixtures.osl, Fixtures.jfk)])]
        )
        let statistics = StatisticsEngine.compute(for: log)
        let headlines = statistics.headlines

        #expect(headlines.map(\.id) == ["countries", "distance", "continents", "flights"])
        let countries = headlines.first { $0.id == "countries" }
        #expect(countries?.value == "1")
        // The layover was excluded, so the countries card must say so.
        #expect(countries?.caveat != nil)
    }

    @Test("Formatted distance follows the unit setting")
    func unitFormatting() {
        let leg = JourneyLeg(
            mode: .flight,
            origin: Fixtures.osl,
            destination: Fixtures.jfk,
            distanceKmOverride: 100
        )
        let log = TravelLog(journeys: [Journey(legs: [leg])])

        #expect(StatisticsEngine.compute(for: log).formattedDistance == "100 km")
        #expect(
            StatisticsEngine.compute(
                for: log,
                rules: CountingRules(unitSystem: .imperial)
            ).formattedDistance == "62 mi"
        )
    }

    @Test("An empty log produces headlines rather than crashing")
    func emptyLog() {
        let statistics = StatisticsEngine.compute(for: .empty)
        #expect(statistics.headlines.count == 4)
        #expect(statistics.formattedDistance == "0 km")
    }
}

@Suite("Stat input bookkeeping")
struct StatInputSummaryTests {
    @Test("Counts what it used and what it dropped")
    func counting() {
        var summary = StatInputSummary()
        summary.include()
        summary.include()
        summary.exclude(.unknownDate)

        #expect(summary.considered == 3)
        #expect(summary.used == 2)
        #expect(summary.excludedCount == 1)
        #expect(!summary.isComplete)
        #expect(abs(summary.completeness - 2.0 / 3.0) < 1e-12)
    }

    @Test("An empty summary is complete, not zero-complete")
    func emptyIsComplete() {
        let summary = StatInputSummary()
        #expect(summary.isComplete)
        #expect(summary.completeness == 1)
        #expect(summary.caveat == nil)
    }

    @Test("The caveat names every reason, most common first")
    func caveatWording() {
        var summary = StatInputSummary()
        summary.include()
        summary.exclude(.unknownDate)
        summary.exclude(.unknownDate)
        summary.exclude(.missingCountry)

        let caveat = summary.caveat
        #expect(caveat?.hasPrefix("Based on 1 of 4 records;") == true)
        #expect(caveat?.contains("2 no date recorded") == true)
        #expect(caveat?.contains("1 no country resolved") == true)
        // Ordering: the bigger exclusion is named first.
        let datePosition = caveat?.range(of: "2 no date recorded")?.lowerBound
        let countryPosition = caveat?.range(of: "1 no country resolved")?.lowerBound
        #expect(datePosition != nil && countryPosition != nil)
        if let datePosition, let countryPosition, let caveat {
            #expect(caveat.distance(from: caveat.startIndex, to: datePosition)
                < caveat.distance(from: caveat.startIndex, to: countryPosition))
        }
    }
}
