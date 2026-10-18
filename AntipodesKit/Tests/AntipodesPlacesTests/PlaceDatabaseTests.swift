import AntipodesCore
import AntipodesPlaces
import Foundation
import Testing

/// Locates the database built by `Tools/placedb/build_placedb.py`.
///
/// These tests run against the real artefact rather than a mock, because the thing
/// most likely to break is the agreement between the Python schema and the Swift
/// queries. They are skipped — visibly — when the database has not been built.
enum PlaceDatabaseFixture {
    static var url: URL {
        URL(fileURLWithPath: #filePath) // …/Tests/AntipodesPlacesTests/x.swift
            .deletingLastPathComponent() // …/Tests/AntipodesPlacesTests
            .deletingLastPathComponent() // …/Tests
            .deletingLastPathComponent() // …/AntipodesKit
            .deletingLastPathComponent() // repository root
            .appending(path: "Tools/placedb/out/places.sqlite")
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    static func open() throws -> PlaceDatabase {
        try PlaceDatabase(path: url.path(percentEncoded: false))
    }
}

@Suite("Place database", .enabled(if: PlaceDatabaseFixture.exists))
struct PlaceDatabaseTests {
    /// M1 acceptance criterion 1.
    @Test("Searching \"oslo\" offline returns the city first, then the airport")
    func searchOslo() async throws {
        let database = try PlaceDatabaseFixture.open()
        let results = try await database.search("oslo")

        #expect(!results.isEmpty)
        #expect(results.first?.kind == .city)
        #expect(results.first?.name == "Oslo")
        #expect(results.contains { $0.kind == .airport && $0.code == "OSL" })
    }

    /// A city must outrank a region of the same name, and a country outrank both.
    @Test("Ranking puts the kind a traveller means first")
    func rankingTiers() async throws {
        let database = try PlaceDatabaseFixture.open()

        let oslo = try await database.search("oslo")
        let cityIndex = try #require(oslo.firstIndex { $0.kind == .city })
        let regionIndex = try #require(oslo.firstIndex { $0.kind == .region })
        #expect(cityIndex < regionIndex)

        let singapore = try await database.search("singapore")
        #expect(singapore.first?.kind == .country)
    }

    @Test("A prefix offers the most prominent match first")
    func prefixRanking() async throws {
        let database = try PlaceDatabaseFixture.open()
        let results = try await database.search("par")
        #expect(results.first?.name == "Paris")
    }

    /// `ø` is its own Unicode letter, not a decomposable diacritic, so this only works
    /// because the pipeline writes a transliterated copy into the index.
    @Test("Unaccented typing finds accented names")
    func accentFolding() async throws {
        let database = try PlaceDatabaseFixture.open()

        let tromso = try await database.search("tromso")
        #expect(tromso.contains { $0.name == "Tromsø" })

        let saoPaulo = try await database.search("sao paulo")
        #expect(saoPaulo.contains { $0.name == "São Paulo" })

        let zurich = try await database.search("zurich")
        #expect(zurich.contains { $0.name == "Zurich" })
    }

    @Test("Type filters narrow the results")
    func kindFilter() async throws {
        let database = try PlaceDatabaseFixture.open()
        let airports = try await database.search("oslo", kinds: [.airport])
        #expect(!airports.isEmpty)
        #expect(airports.allSatisfy { $0.kind == .airport })
    }

    @Test("An airport can be found by IATA or ICAO code")
    func airportByCode() async throws {
        let database = try PlaceDatabaseFixture.open()

        let byIATA = try #require(try await database.airport(code: "OSL"))
        #expect(byIATA.name == "Oslo Gardermoen")
        #expect(byIATA.countryCode == "NO")
        #expect(byIATA.coordinate != nil)

        #expect(try await database.airport(code: "osl") != nil) // case-insensitive
        #expect(try await database.airport(code: "ZZZ") == nil)
        #expect(try await database.airport(code: "X") == nil) // too short to be a code
    }

    /// R-MODEL-6: the reference a landmark produces must carry its city, region and
    /// country, or coverage stats under-count.
    @Test("A landmark search result carries its whole hierarchy")
    func hierarchyInResults() async throws {
        let database = try PlaceDatabaseFixture.open()
        let results = try await database.search("colosseum")
        let colosseum = try #require(results.first { $0.kind == .landmark })

        #expect(colosseum.countryCode == "IT")
        #expect(colosseum.countryName == "Italy")
        #expect(colosseum.continent == .europe)
        #expect(colosseum.cityName == "Rome")
        #expect(colosseum.cityID != nil)
        #expect(colosseum.regionCode == "IT-62")

        let reference = colosseum.placeReference
        #expect(reference.impliedCityID == colosseum.cityID)
        #expect(reference.qualifiedRegionCode == "IT-62")
    }

    @Test("A search with no matches returns nothing rather than throwing")
    func noMatches() async throws {
        let database = try PlaceDatabaseFixture.open()
        #expect(try await database.search("zzzzqqqq").isEmpty)
        #expect(try await database.search("").isEmpty)
    }

    /// Parameters are bound, never interpolated, so this is just a search for odd text.
    @Test("A query full of SQL and FTS5 syntax is treated as text")
    func injectionIsJustText() async throws {
        let database = try PlaceDatabaseFixture.open()
        #expect(try await database.search("'; DROP TABLE city; --").isEmpty)
        #expect(try await database.search("\" OR 1=1 --").isEmpty)
    }

    @Test("A place can be fetched back by its identity")
    func lookupByID() async throws {
        let database = try PlaceDatabaseFixture.open()
        let results = try await database.search("oslo", kinds: [.city])
        let oslo = try #require(results.first)
        guard case let .database(kind, row) = oslo.id else {
            Issue.record("A database result should carry a database id")
            return
        }
        let fetched = try #require(try await database.place(kind: kind, id: row))
        #expect(fetched.name == oslo.name)
        #expect(fetched.id == oslo.id)
    }

    /// R-LOG-5: a dropped pin has to resolve to a country or it cannot count towards
    /// coverage. Nearest-country-centroid is a stand-in for real point-in-polygon
    /// geocoding, so this only asserts that it resolves something sensible.
    @Test("A dropped pin resolves to a country without a network call")
    func pinGeocoding() async throws {
        let database = try PlaceDatabaseFixture.open()
        let nearOslo = Coordinate(latitude: 59.9, longitude: 10.7)
        let country = try #require(try await database.approximateCountry(for: nearOslo))
        #expect(country.kind == .country)
        #expect(country.countryCode != nil)
    }

    @Test("The database reports its version and row counts")
    func databaseInfo() async throws {
        let database = try PlaceDatabaseFixture.open()
        let info = try await database.info()

        #expect(info.schemaVersion == PlaceDatabase.expectedSchemaVersion)
        #expect(info.dataVersion != "unknown")
        #expect(info.totalRows > 0)
        #expect((info.rowCounts[.country] ?? 0) > 0)
        #expect((info.rowCounts[.city] ?? 0) > 0)
        #expect((info.rowCounts[.airport] ?? 0) > 0)
    }

    @Test("Opening a database that is not there fails with a useful message")
    func missingFile() {
        #expect(throws: PlaceDatabaseError.self) {
            _ = try PlaceDatabase(path: "/nonexistent/places.sqlite")
        }
    }
}
