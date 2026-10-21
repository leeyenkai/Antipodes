import AntipodesCore
import AntipodesStats
import Foundation
import Testing

/// The parts of §5.7 and §7 finished in the release audit: road and sea, the records
/// behind each place attribute, and the journey figures that had been measured wrongly.
@Suite("Road and sea, and the records behind the figures")
struct CompletenessTests {
    static func place(_ name: String, _ country: String, _ latitude: Double, _ longitude: Double)
        -> PlaceReference {
        PlaceReference(
            id: .custom(UUID()),
            kind: .custom,
            name: name,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            countryCode: country
        )
    }

    static let oslo = place("Oslo", "NO", 59.91, 10.75)
    static let kiel = place("Kiel", "DE", 54.32, 10.14)
    static let bergen = place("Bergen", "NO", 60.39, 5.33)
    static let hirtshals = place("Hirtshals", "DK", 57.59, 9.96)
    static let anchorage = place("Anchorage", "US", 61.17, -149.99)
    static let day = FlexibleDate.day(CalendarDate(iso: "2024-07-02")!)

    /// Two road trips (120 km entered, and one between places with no coordinates, so
    /// no distance) and three ferries: Oslo–Kiel 160 km on the Color Magic, Bergen–
    /// Hirtshals 60 km on "a catamaran" with no name, and a commute ferry, which the
    /// default rules leave out.
    @Test("Road and sea counts drives, ferries, the longest crossing and the ships")
    func roadAndSea() {
        let nowhere = PlaceReference(id: .custom(UUID()), kind: .custom, name: "Somewhere")
        let log = TravelLog(journeys: [
            Journey(legs: [
                JourneyLeg(
                    mode: .roadTrip,
                    origin: Self.oslo,
                    destination: Self.bergen,
                    date: Self.day,
                    distanceKmOverride: 120
                ),
            ]),
            Journey(legs: [JourneyLeg(mode: .roadTrip, origin: nowhere, destination: nowhere)]),
            Journey(legs: [
                JourneyLeg(
                    mode: .ferry,
                    origin: Self.oslo,
                    destination: Self.kiel,
                    date: Self.day,
                    distanceKmOverride: 160,
                    operatorName: "Color Line",
                    registration: "Color Magic"
                ),
            ]),
            Journey(legs: [
                JourneyLeg(
                    mode: .ferry,
                    origin: Self.bergen,
                    destination: Self.hirtshals,
                    date: Self.day,
                    distanceKmOverride: 60,
                    vehicle: "Catamaran"
                ),
            ]),
            Journey(legs: [
                JourneyLeg(
                    mode: .ferry,
                    origin: Self.oslo,
                    destination: Self.bergen,
                    purpose: .commute,
                    distanceKmOverride: 500
                ),
            ]),
        ])
        let stats = RoadAndSeaStatistics.compute(for: log)
        #expect(stats.roadTripLegs == 2)
        #expect(stats.kilometresDriven == 120)
        #expect(stats.roadInput.used == 1)
        #expect(stats.ferriesTaken == 2)
        #expect(stats.seaKilometres == 220)
        #expect(stats.longestSeaCrossing?.destination.name == "Kiel")
        #expect(stats.ships == ["Color Magic", "Catamaran"])
        #expect(stats.ferryOperators == ["Color Line"])
        #expect(stats.seaInput.used == 2)
        #expect(stats.seaInput.excludedCount == 1)
    }

    /// One flight of 8,000 km on its own, and a two-leg rail journey of 300 + 200 km.
    /// The single flight is the longest leg; the rail journey is the longest journey
    /// of more than one leg.
    @Test("The longest journey is the longest made of connections")
    func longestMultiLegJourney() {
        let log = TravelLog(journeys: [
            Journey(legs: [
                JourneyLeg(
                    mode: .flight,
                    origin: Self.oslo,
                    destination: Self.anchorage,
                    distanceKmOverride: 8000
                ),
            ]),
            Journey(legs: [
                JourneyLeg(
                    mode: .rail,
                    origin: Self.oslo,
                    destination: Self.bergen,
                    distanceKmOverride: 300
                ),
                JourneyLeg(
                    mode: .rail,
                    origin: Self.bergen,
                    destination: Self.oslo,
                    distanceKmOverride: 200
                ),
            ]),
        ])
        let stats = DistanceStatistics.compute(for: log)
        #expect(stats.longestLeg?.distanceKm == 8000)
        #expect(stats.longestJourney?.totalDistanceKm == 500)
    }

    /// The Bergen Line runs Oslo–Bergen inside Norway; a made-up "Nordic Arc" runs
    /// Oslo–Bergen through Norway, Sweden and Denmark. Ridden in full, its countries
    /// count overland and on the rails even though both ends are Norwegian.
    @Test("A catalogue route ridden in full adds the countries it runs through")
    func routeCountries() {
        let arc = RouteInfo(
            id: 9,
            name: "Nordic Arc",
            mode: .rail,
            start: Self.oslo,
            end: Self.bergen,
            countryCodes: ["NO", "SE", "DK"]
        )
        let log = TravelLog(journeys: [
            Journey(legs: [
                JourneyLeg(
                    mode: .rail,
                    origin: Self.oslo,
                    destination: Self.bergen,
                    routeID: 9
                ),
            ]),
        ])
        let journeys = JourneyStatistics.compute(for: log, routes: [arc])
        #expect(journeys.countriesOverland == ["NO", "SE", "DK"])
        let rail = RailStatistics.compute(for: log, routes: [arc])
        #expect(rail.countries == ["NO", "SE", "DK"])
    }

    /// Oslo (59.9° N) to Anchorage (61.2° N) is 160.7° of longitude apart, so the great
    /// circle tops out near 84.6° N: tan φ = tan 60.5° / cos 80.4°. Neither end is
    /// inside the Arctic Circle; the flight is.
    @Test("A polar flight crosses the Arctic Circle without landing inside it")
    func polarFlight() {
        let log = TravelLog(journeys: [
            Journey(legs: [
                JourneyLeg(
                    mode: .flight,
                    origin: Self.oslo,
                    destination: Self.anchorage,
                    date: Self.day
                ),
            ]),
        ])
        let badge = AchievementDefinition(
            id: "arctic",
            name: "Arctic",
            description: "",
            rule: .arcticCircle,
            threshold: 1
        )
        let status = AchievementEngine.evaluate([badge], log: log)
        #expect(status.first?.isEarned == true)
        #expect(status.first?.earnedOn?.iso == "2024-07-02")

        // The same two ends by road prove nothing about the way between.
        let drive = TravelLog(journeys: [
            Journey(legs: [
                JourneyLeg(
                    mode: .roadTrip,
                    origin: Self.oslo,
                    destination: Self.anchorage,
                    date: Self.day
                ),
            ]),
        ])
        #expect(AchievementEngine.evaluate([badge], log: drive).first?.isEarned == false)
    }

    /// Two UNESCO sites on one trip, on 3 and 5 May: two in one trip is earned on the
    /// 5th, the day the second was seen.
    @Test("UNESCO sites in one trip are earned on the day of the last one needed")
    func unescoInOneTripDate() throws {
        let trip = Trip(name: "Italy")
        let forum = PlaceReference(id: .database(.landmark, 30), kind: .landmark, name: "Forum")
        let pompeii = PlaceReference(id: .database(.landmark, 31), kind: .landmark, name: "Pompeii")
        let gazetteer = Gazetteer(places: [
            forum.id: PlaceFacts(isUNESCO: true),
            pompeii.id: PlaceFacts(isUNESCO: true),
        ])
        let log = try TravelLog(trips: [trip], visits: [
            Visit(
                place: forum,
                date: .day(#require(CalendarDate(iso: "2024-05-03"))),
                tripID: trip.id
            ),
            Visit(
                place: pompeii,
                date: .day(#require(CalendarDate(iso: "2024-05-05"))),
                tripID: trip.id
            ),
        ])
        let badge = AchievementDefinition(
            id: "unesco",
            name: "UNESCO",
            description: "",
            rule: .unescoInOneTrip,
            threshold: 2
        )
        let status = AchievementEngine.evaluate([badge], log: log, gazetteer: gazetteer)
        #expect(status.first?.isEarned == true)
        #expect(status.first?.earnedOn?.iso == "2024-05-05")
    }

    /// Norway's main language is Norwegian and Italy's Italian (its list also has
    /// German); both use their own currency, so each list has one country under it.
    /// Two landmarks, built in 80 and 1173, come out oldest first.
    @Test("Each place attribute lists the records behind it")
    func recordsBehindAttributes() {
        let colosseum = PlaceReference(
            id: .database(.landmark, 20),
            kind: .landmark,
            name: "Colosseum",
            countryCode: "IT"
        )
        let pisa = PlaceReference(
            id: .database(.landmark, 21),
            kind: .landmark,
            name: "Leaning Tower",
            countryCode: "IT"
        )
        let oslo = PlaceReference(
            id: .database(.city, 10),
            kind: .city,
            name: "Oslo",
            countryCode: "NO"
        )
        let gazetteer = Gazetteer(
            places: [
                colosseum.id: PlaceFacts(yearBuilt: 80),
                pisa.id: PlaceFacts(yearBuilt: 1173),
            ],
            countries: [
                "NO": CountryFacts(
                    code: "NO",
                    name: "Norway",
                    continent: .europe,
                    currencyCode: "NOK",
                    languageCodes: ["no"]
                ),
                "IT": CountryFacts(
                    code: "IT",
                    name: "Italy",
                    continent: .europe,
                    currencyCode: "EUR",
                    languageCodes: ["it-IT", "de-IT"]
                ),
            ]
        )
        let log = TravelLog(visits: [
            Visit(place: pisa),
            Visit(place: colosseum),
            Visit(place: oslo),
        ])
        let stats = PlaceAttributeStatistics.compute(
            for: log,
            gazetteer: gazetteer,
            referenceYear: 2026
        )
        #expect(stats.landmarksByYear.map(\.place.name) == ["Colosseum", "Leaning Tower"])
        #expect(stats.countriesByLanguage == ["no": ["NO"], "it": ["IT"]])
        #expect(stats.countriesByCurrency == ["NOK": ["NO"], "EUR": ["IT"]])
        #expect(stats.languageCodes == ["no", "it"])
    }
}
