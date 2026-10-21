import AntipodesCore
@testable import AntipodesPlaces
import Foundation
import Testing

@Suite("Place catalogue", .enabled(if: PlaceDatabaseFixture.exists))
struct PlaceCatalogueTests {
    /// A user's log stores these ids, and the database is replaced by updates (R-DB-5),
    /// so they must be the upstream identifiers, not positions in a sorted list.
    @Test("Row ids are the upstream identities, so they survive any rebuild")
    func stableIdentifiers() async throws {
        let database = try PlaceDatabaseFixture.open()

        let oslo = try #require(try await database.search("oslo").first { $0.kind == .city })
        #expect(oslo.id == .database(.city, 3_143_244)) // GeoNames id

        let norway = try #require(try await database.country(code: "NO"))
        #expect(norway.id == .database(.country, 1415)) // N = 14, O = 15

        let colosseum = try #require(try await database.search("colosseum")
            .first { $0.kind == .landmark })
        #expect(colosseum.id == .database(.landmark, 10285)) // Q10285
    }

    @Test("Search results carry the time zone legs are read in")
    func timeZones() async throws {
        let database = try PlaceDatabaseFixture.open()
        #expect(try await database.airport(code: "OSL")?.timeZoneIdentifier == "Europe/Oslo")
        #expect(try await database.airport(code: "JFK")?.timeZoneIdentifier == "America/New_York")
        let oslo = try await database.search("oslo", kinds: [.city]).first
        #expect(oslo?.timeZoneIdentifier == "Europe/Oslo")
        #expect(oslo?.placeReference.timeZoneIdentifier == "Europe/Oslo")
        #expect(try await database.airport(code: "OSL")?.placeReference.code == "OSL")
    }

    @Test("Facts are returned for each kind the statistics read")
    func facts() async throws {
        let database = try PlaceDatabaseFixture.open()
        let ids: [PlaceID] = [.database(.city, 3_143_244), .database(.landmark, 10285)]
        let facts = try await database.facts(for: ids)

        let oslo = try #require(facts[.database(.city, 3_143_244)])
        #expect(oslo.isCapital)
        #expect((oslo.population ?? 0) > 500_000)
        #expect(oslo.timeZoneIdentifier == "Europe/Oslo")

        let colosseum = try #require(facts[.database(.landmark, 10285)])
        #expect(colosseum.yearBuilt == 82) // Wikidata P571, as built
        #expect(colosseum.themes.contains("ancient-history"))

        let countries = try await database.countryFacts()
        #expect(countries["NO"]?.currencyCode == "NOK")
        #expect(countries["NO"]?.isUNMember == true)
        #expect(countries["GL"]?.isUNMember == false)
        #expect(countries.count == 252)
    }

    /// TerraClimate's 1991-2020 normals put Oslo's July near 17 °C and its January
    /// below freezing, and the published Köppen-Geiger maps call it Dfb; Singapore is Af
    /// and Cairo BWh. The test allows a degree either way: the figures come from a
    /// 28 km grid corrected to the city's elevation, not from a single station.
    @Test("Climate normals and zones arrive with the facts")
    func climate() async throws {
        let database = try PlaceDatabaseFixture.open()
        let ids: [PlaceID] = [
            .database(.city, 3_143_244), .database(.city, 1_880_252), .database(.city, 360_630),
        ]
        let facts = try await database.facts(for: ids)
        let oslo = try #require(facts[.database(.city, 3_143_244)]?.monthlyMeanTemperatureC)
        #expect(abs(oslo[6] - 17) < 1.5)
        #expect(oslo[0] < 0)
        #expect(facts[.database(.city, 3_143_244)]?.koppen == "Dfb")
        #expect(facts[.database(.city, 1_880_252)]?.koppen == "Af")
        #expect(facts[.database(.city, 360_630)]?.koppen == "BWh")
    }

    /// Stelvio (Q1334855) is filed as a mountain pass. The Parthenon's inception is
    /// known only to the century (Wikidata: 5th century BC), so it carries an era and no
    /// made-up year (R-DB-3).
    @Test("Passes have their kind and century-precise landmarks an era")
    func passesAndEras() async throws {
        let database = try PlaceDatabaseFixture.open()
        let stelvio = PlaceID.database(.landmark, 1_334_855)
        let parthenon = PlaceID.database(.landmark, 10288)
        let facts = try await database.facts(for: [stelvio, parthenon])
        #expect(facts[stelvio]?.landmarkKind == "mountain pass")
        #expect(facts[parthenon]?.era == "5th century BC")
        #expect(facts[parthenon]?.yearBuilt == nil)
    }

    @Test("Every collection resolves to members, and the New 7 Wonders are all there")
    func collections() async throws {
        let database = try PlaceDatabaseFixture.open()
        let collections = try await database.collections()
        #expect(collections.count >= 5)
        #expect(collections.allSatisfy { !$0.members.isEmpty })

        let wonders = try #require(collections.first { $0.id == "new-7-wonders" })
        #expect(wonders.members.count == 7)
        #expect(wonders.members.contains { $0.name == "Machu Picchu" })

        let parks = try #require(collections.first { $0.id == "us-national-parks" })
        #expect(parks.members.count == 63)

        let nordic = try #require(collections.first { $0.id == "nordic-capitals" })
        #expect(Set(nordic.members.map(\.name)) == [
            "Copenhagen",
            "Helsinki",
            "Reykjavík",
            "Oslo",
            "Stockholm",
        ])
    }

    /// Every achievement the database ships must be one this build can evaluate, or the
    /// screen would silently hide it.
    @Test("Every shipped achievement uses a rule this build knows")
    func achievements() async throws {
        let database = try PlaceDatabaseFixture.open()
        let achievements = try await database.achievements()
        #expect(achievements.count >= 30)
        #expect(achievements.allSatisfy { $0.rule != nil })
        let collections = try await Set(database.collections().map(\.id))
        for achievement in achievements where achievement.rule == .collectionComplete {
            #expect(collections.contains(achievement.parameter ?? ""))
        }
    }

    @Test("Routes resolve their ends to bundled places where they can")
    func routes() async throws {
        let database = try PlaceDatabaseFixture.open()
        let routes = try await database.routes()
        let bergenLine = try #require(routes.first { $0.name == "Bergen Line" })
        #expect(bergenLine.mode == .rail)
        #expect(bergenLine.start?.name == "Oslo")
        #expect(bergenLine.end?.name == "Bergen")
        #expect(bergenLine.lengthKm == 496)
        // Myrdal and Flåm are too small for the bundled city set, so the ends stay open.
        let flam = try #require(routes.first { $0.id == 3 })
        #expect(flam.start == nil)
        #expect(flam.end == nil)
    }

    /// R-CO2-3: every carbon figure names its source and year, so both must be there.
    @Test("Carbon factors cover the motorised modes and say where they are from")
    func emissionFactors() async throws {
        let database = try PlaceDatabaseFixture.open()
        let table = try await database.emissionFactors()
        #expect(table.year == 2025)
        #expect(table.sourceName.contains("DESNZ"))
        for mode in [TravelMode.flight, .rail, .cityTransit, .coach, .ferry, .roadTrip] {
            #expect(table.factor(for: mode, travelClass: nil) != nil, "no factor for \(mode)")
        }
        let business = try #require(table.factor(for: .flight, travelClass: "Business"))
        let economy = try #require(table.factor(for: .flight, travelClass: "Economy"))
        #expect(business.kgCO2ePerKm > economy.kgCO2ePerKm)
        #expect(table.factor(for: .roadTrip, travelClass: nil)?.basis == .vehicle)
    }

    @Test("A coordinate is named by the nearest bundled city within range")
    func nearestCity() async throws {
        let database = try PlaceDatabaseFixture.open()
        // Trondheim's Nidaros Cathedral.
        let near = try await database.nearestCity(to: Coordinate(
            latitude: 63.4269,
            longitude: 10.3969
        ))
        #expect(near?.name == "Trondheim")
        // The middle of the Atlantic has no city within 40 km.
        #expect(try await database.nearestCity(to: Coordinate(latitude: 30, longitude: -40)) == nil)
    }

    @Test("The theme taxonomy ships with its labels")
    func themes() async throws {
        let database = try PlaceDatabaseFixture.open()
        let themes = try await database.themes()
        #expect(themes.count == 17)
        #expect(themes.first { $0.id == "nightlife" }?.label == "Nightlife")
        #expect(themes.first { $0.id == "national-parks" }?.label == "Parks")
    }

    /// GeoNames writes -9999 where its elevation model has no reading. Shipped as a
    /// number, it made Tromsø the lowest place anyone had visited.
    @Test("No-data elevations are stored as unknown, not as -9999 m")
    func elevationSentinel() async throws {
        let database = try PlaceDatabaseFixture.open()
        let sentinels = try await database.count(
            "SELECT COUNT(*) FROM city WHERE elevation_m <= -1000"
        ) + database.count("SELECT COUNT(*) FROM airport WHERE elevation_m <= -1000")
        #expect(sentinels == 0)
    }
}
