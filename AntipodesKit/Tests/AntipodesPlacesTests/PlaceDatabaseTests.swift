import AntipodesCore
@testable import AntipodesPlaces
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

        // GeoNames spells the city "Zürich" and the region "Zurich", so this has to
        // name the kind or it passes on the wrong row.
        let zurich = try await database.search("zurich")
        #expect(zurich.contains { $0.kind == .city && $0.name == "Zürich" })
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
        // OurAirports' own name for it. The seed used to say "Oslo Gardermoen".
        #expect(byIATA.name == "Oslo-Gardermoen International Airport")
        #expect(byIATA.countryCode == "NO")
        #expect(byIATA.coordinate != nil)

        #expect(try await database.airport(code: "osl") != nil) // case-insensitive

        // ICAO is not in the search index; it has to come from the airport table.
        let byICAO = try #require(try await database.airport(code: "ENGM"))
        #expect(byICAO.id == byIATA.id)
        #expect(try await database.airport(code: "egll")?.code == "LHR")
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
        // GeoNames' admin1 code, not ISO 3166-2: the two are different levels in Italy
        // (ISO's IT-62 is the region Lazio, while Natural Earth's admin-1 layer gives
        // Italy its provinces). See the note on `region.code` in schema.sql.
        #expect(colosseum.regionCode == "IT.07")
        #expect(colosseum.regionName == "Lazio")

        let reference = colosseum.placeReference
        #expect(reference.impliedCityID == colosseum.cityID)
        #expect(reference.qualifiedRegionCode == "IT.07")
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
    /// coverage. Nearest-bundled-city is a stand-in for real point-in-polygon
    /// geocoding, but it is accurate enough well inside a border to name the country.
    @Test("A dropped pin resolves to a country without a network call")
    func pinGeocoding() async throws {
        let database = try PlaceDatabaseFixture.open()

        let nearOslo = Coordinate(latitude: 59.9, longitude: 10.7)
        let norway = try #require(try await database.approximateCountry(for: nearOslo))
        #expect(norway.kind == .country)
        #expect(norway.countryCode == "NO")
        #expect(norway.continent == .europe)

        // Somewhere with no nearby city at all still has to resolve rather than throw,
        // even though the answer is only the nearest coast.
        let midAtlantic = Coordinate(latitude: 0, longitude: -30)
        #expect(try await database.approximateCountry(for: midAtlantic) != nil)
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
        #expect(info.citiesDataset.hasPrefix("cities"))

        // Real data, not the old hand-entered seed: the seed had 60 countries and 86
        // cities, so these floors can only be met by the built pipeline.
        #expect((info.rowCounts[.country] ?? 0) >= 193)
        #expect((info.rowCounts[.city] ?? 0) > 10000)
        #expect((info.rowCounts[.landmark] ?? 0) >= 200)
    }

    @Test("Opening a database that is not there fails with a useful message")
    func missingFile() {
        #expect(throws: PlaceDatabaseError.self) {
            _ = try PlaceDatabase(path: "/nonexistent/places.sqlite")
        }
    }

    // MARK: - Ranking cases the real data exposed

    /// A famous city must outrank a country whose name merely starts the same way.
    ///
    /// The seed had too few countries to show this. Against the real list, "par"
    /// matches Paraguay, and the old ranking multiplied the place kind by a billion, so
    /// *every* country outranked *every* city. Paraguay came first.
    @Test("A prominent city outranks a country with the same prefix")
    func cityOutranksCountryOnPrefix() async throws {
        let database = try PlaceDatabaseFixture.open()
        let results = try await database.search("par")

        let paris = try #require(results.firstIndex { $0.name == "Paris" && $0.kind == .city })
        let paraguay = try #require(results.firstIndex { $0.name == "Paraguay" })
        #expect(paris < paraguay)
        #expect(results.first?.name == "Paris")
    }

    /// An exact match on an obscure place must not leapfrog a famous one.
    ///
    /// "Par" is a village in Cornwall, and it matches the query "par" exactly. Ranking
    /// every exact match first put it above Paris, which is why
    /// ``PlaceDatabase/exactMatchProminenceFloor`` exists.
    @Test("An obscure exact match does not outrank a prominent prefix match")
    func exactMatchFloor() async throws {
        let database = try PlaceDatabaseFixture.open()
        let results = try await database.search("par")

        if let par = results.firstIndex(where: { $0.name == "Par" }) {
            let paris = try #require(results.firstIndex { $0.name == "Paris" })
            #expect(paris < par)
        }
        // The floor must not break the ordinary case: a place prominent enough to clear
        // it still wins its exact match outright.
        let bath = try await database.search("bath")
        #expect(bath.first?.name == "Bath")
    }

    /// Among rows that match exactly, the kind decides — this is the case the floor
    /// must not break.
    @Test("An exact match prefers the country, then the city, then the region")
    func exactMatchPrefersKind() async throws {
        let database = try PlaceDatabaseFixture.open()

        let singapore = try await database.search("singapore")
        #expect(singapore.first?.kind == .country)

        // "oslo" matches a city, a county and an airport. All three should appear, in
        // that order: the city and the region both match the name exactly so the kind
        // separates them, and the airport only matches as a prefix.
        let oslo = try await database.search("oslo")
        let city = try #require(oslo.firstIndex { $0.kind == .city && $0.name == "Oslo" })
        let region = try #require(oslo.firstIndex { $0.kind == .region })
        let airport = try #require(oslo.firstIndex { $0.kind == .airport })
        #expect(city < region)
        #expect(region < airport)
    }

    /// An accented name can only be matched exactly if the index carries a folded copy,
    /// and the ranking consequences are severe without one: "malmo" put *Malmok*, a
    /// hamlet in Aruba, and an airport ahead of Malmö, and "zurich" put the canton
    /// ahead of the city.
    @Test("An unaccented query matches an accented name exactly, not just loosely")
    func foldedNamesRankAsExactMatches() async throws {
        let database = try PlaceDatabaseFixture.open()

        for (query, expected) in [
            ("malmo", "Malmö"),
            ("zurich", "Zürich"),
            ("tromso", "Tromsø"),
            ("koln", "Köln"),
        ] {
            let results = try await database.search(query)
            let first = try #require(results.first)
            #expect(
                first.kind == .city && first.name == expected,
                "\(query) gave \(first.kind) \(first.name), expected the city \(expected)"
            )
        }

        // A region is a plausible second hit but must not displace a city: its
        // prominence is the population of its own cities, damped.
        let lazio = try await database.search("lazio")
        #expect(lazio.first?.kind == .region)
        #expect(lazio.first?.name == "Lazio")
    }

    // MARK: - Licensing and provenance

    /// R-DB-7. Attribution is a licence condition, so the app cannot be allowed to
    /// ship a database whose sources it does not name.
    @Test("Every source is registered, and the ones that require credit carry it")
    func dataSourcesAreRegistered() async throws {
        let database = try PlaceDatabaseFixture.open()
        let sources = try await database.dataSources()

        #expect(sources.count >= 4)

        let geonames = try #require(sources.first { $0.id == "geonames" })
        #expect(geonames.licence == "CC BY 4.0")
        let credit = try #require(geonames.attribution)
        // CC BY 4.0 §3(a) wants the creator, the licence and an indication of changes.
        #expect(credit.contains("GeoNames"))
        #expect(credit.contains("CC BY 4.0"))
        #expect(credit.contains("modified"))

        #expect(try await database.info().requiredAttributions.contains(credit))

        // Public-domain and CC0 sources must not invent an obligation they do not have.
        for id in ["naturalearth", "ourairports", "wikidata"] {
            let source = try #require(sources.first { $0.id == id })
            #expect(source.attribution == nil)
        }
    }

    /// The ODbL share-alike question is unresolved for a shipped derived database, so
    /// no OpenStreetMap-derived row may be in this file at all (R-DB-7, SOURCES.md).
    /// Trainline's stations dataset is ODbL too and is covered by the same check.
    @Test("No OpenStreetMap-derived source is present")
    func noShareAlikeSources() async throws {
        let database = try PlaceDatabaseFixture.open()
        let sources = try await database.dataSources()

        for source in sources {
            #expect(!source.licence.lowercased().contains("odbl"))
            #expect(!source.name.lowercased().contains("openstreetmap"))
            #expect(!source.name.lowercased().contains("trainline"))
        }
    }

    /// Every row names a source that is actually registered, or the attribution list in
    /// Settings is incomplete without anyone noticing.
    @Test("Every row's source names a registered data source")
    func everyRowHasAKnownSource() async throws {
        let database = try PlaceDatabaseFixture.open()
        for table in ["country", "region", "city", "landmark", "airport", "route"] {
            let orphans = try await database.count(
                """
                SELECT COUNT(*) FROM \(table)
                WHERE source IS NULL OR source NOT IN (SELECT id FROM data_source)
                """
            )
            #expect(orphans == 0, "\(table) has \(orphans) rows with an unregistered source")
        }
    }

    // MARK: - Curation rules

    /// R-DB-1: a landmark with no theme makes the personality stats under-count, so the
    /// pipeline refuses to write one. This checks the artefact, not the pipeline.
    @Test("Every landmark carries at least one theme tag")
    func everyLandmarkHasATheme() async throws {
        let database = try PlaceDatabaseFixture.open()
        let untagged = try await database.count(
            "SELECT COUNT(*) FROM landmark WHERE themes IS NULL OR trim(themes) = ''"
        )
        #expect(untagged == 0)
    }

    /// R-MODEL-6: a landmark implies its city, region and country. A landmark with a
    /// city but no region would break that chain for coverage stats.
    @Test("A landmark with a city also carries that city's region")
    func landmarkHierarchyIsComplete() async throws {
        let database = try PlaceDatabaseFixture.open()
        let broken = try await database.count(
            """
            SELECT COUNT(*) FROM landmark AS l
            JOIN city AS c ON c.id = l.city_id
            WHERE c.region_code IS NOT NULL AND l.region_code IS NULL
            """
        )
        #expect(broken == 0)
    }

    /// Q-4, decision D-6: the denominator for "% of the world" comes from the database
    /// so the user can choose a list, and 193 UN members is the number that must hold.
    @Test("The country lists carry the counts the app divides by")
    func countryListCounts() async throws {
        let database = try PlaceDatabaseFixture.open()
        let counts = try await database.countryListCounts()

        #expect(counts[.unMembers] == 193)
        #expect(counts[.unMembersAndObservers] == 195)
        let territories = try #require(counts[.allCountriesAndTerritories])
        #expect(territories > 195)

        // The rules pick the real count up, rather than staying on the compiled-in one.
        var rules = CountingRules(countryList: .allCountriesAndTerritories)
        rules.applyCountryCounts(counts)
        #expect(rules.worldCountryCount == territories)
    }

    /// Nothing may be guessed (R-DB-2): a coordinate outside the valid range, or a
    /// landmark or city without one, means a bad row reached the file.
    @Test("Every coordinate in the database is in range")
    func coordinatesAreValid() async throws {
        let database = try PlaceDatabaseFixture.open()
        for table in ["city", "landmark", "airport"] {
            let bad = try await database.count(
                """
                SELECT COUNT(*) FROM \(table)
                WHERE latitude IS NULL OR longitude IS NULL
                   OR latitude < -90 OR latitude > 90
                   OR longitude < -180 OR longitude > 180
                """
            )
            #expect(bad == 0, "\(table) has \(bad) rows with a bad coordinate")
        }
    }

    /// A duplicate IATA code makes `airport(code:)` return an arbitrary one of two
    /// airports. The pipeline fails on it; this proves the shipped file is clean.
    @Test("IATA codes are unique")
    func iataCodesAreUnique() async throws {
        let database = try PlaceDatabaseFixture.open()
        let duplicates = try await database.count(
            """
            SELECT COUNT(*) FROM (
                SELECT iata FROM airport WHERE iata IS NOT NULL
                GROUP BY iata HAVING COUNT(*) > 1
            )
            """
        )
        #expect(duplicates == 0)
    }
}

extension PlaceDatabase {
    /// Runs a counting query for the whole-table invariants above.
    ///
    /// Lives in the test target rather than the module because the app has no reason to
    /// ask any of these questions — they are assertions about the build product.
    func count(_ sql: String) throws -> Int {
        try connection.queryOne(sql) { try $0.int(0) ?? 0 } ?? 0
    }
}

@Suite("Opening the database")
struct SQLiteOpeningTests {
    /// The checkout's own path has a "+" in it; "?", "#" and "%" are the characters a
    /// SQLite URI reads specially, so they must reach the file system as themselves.
    @Test("A path becomes an immutable file URI with its special characters escaped")
    func uri() {
        #expect(SQLiteConnection.immutableURI("/a+b/c d/places.sqlite")
            == "file:/a+b/c d/places.sqlite?immutable=1")
        #expect(SQLiteConnection.immutableURI("/x?y#z%/p.sqlite")
            == "file:/x%3Fy%23z%25/p.sqlite?immutable=1")
    }
}
