import AntipodesCore
@testable import AntipodesPlaces
import Foundation
import Testing

/// The transit packs as the app reads them (R-TRAN-1 to R-TRAN-5), against the built
/// database: the Wikidata links must route a real ride stop by stop.
@Suite("Transit packs", .enabled(if: PlaceDatabaseFixture.exists))
struct PlaceTransitTests {
    /// London Underground (Q20075), Central line (Q205355).
    static let london: Int64 = 20075
    static let central: Int64 = 205_355
    static let oxfordCircus: Int64 = 678_791
    static let holborn: Int64 = 1_433_544
    static let bank: Int64 = 140_030_077

    @Test("The launch set lists London with its city and country")
    func systems() async throws {
        let database = try PlaceDatabaseFixture.open()
        let systems = try await database.transitSystems()
        let london = try #require(systems.first { $0.id == Self.london })
        #expect(london.name == "London Underground")
        #expect(london.cityName == "London")
        #expect(london.countryCode == "GB")
        #expect(london.networkVersion.hasPrefix("wikidata-"))
        // Wikidata files the East London line under the Underground; the fixes drop it.
        let network = try await database.transitNetwork(systems: [Self.london])
        #expect(!network.lines.values.contains { $0.name == "East London Line" })
    }

    @Test("Oxford Circus to Bank on the Central line passes through Holborn")
    func routesARide() async throws {
        let database = try PlaceDatabaseFixture.open()
        let network = try await database.transitNetwork(systems: [Self.london])
        #expect(network.lines[Self.central]?.name == "Central line")

        let path = try #require(network.route(
            onLine: Self.central,
            from: Self.oxfordCircus,
            to: Self.bank
        ))
        #expect(path.first == Self.oxfordCircus)
        #expect(path.last == Self.bank)
        #expect(path.contains(Self.holborn))
        // Oxford Circus, Tottenham Court Road, Holborn, Chancery Lane, St Paul's, Bank.
        #expect(path.count == 6)
        // About 3.6 km along the line; a straight line is about 3.5.
        let length = try #require(network.lengthKm(of: path))
        #expect(length > 3.3 && length < 4.2)

        let systems = try await database.transitSystems(ofLines: [Self.central])
        #expect(systems == [Self.london])
    }

    @Test("A stop is a station in its system's city")
    func stopPlace() async throws {
        let database = try PlaceDatabaseFixture.open()
        let stop = try #require(try await database.transitStopPlace(id: Self.oxfordCircus))
        #expect(stop.kind == .station)
        #expect(stop.name == "Oxford Circus")
        #expect(stop.countryCode == "GB")
        #expect(stop.cityName == "London")
        #expect(stop.continent == .europe)
        #expect(stop.timeZoneIdentifier == "Europe/London")
    }

    @Test("East Asian stops lose the word \"Station\" unless it is the name")
    func stationNames() async throws {
        let database = try PlaceDatabaseFixture.open()
        let tokyo = try #require(try await database.transitSystems().first {
            $0.name == "Tokyo subway"
        })
        let network = try await database.transitNetwork(systems: [tokyo.id])
        let names = Set(network.stops.values.map(\.name))
        #expect(names.contains("Asakusa"))
        #expect(names.contains("Tokyo Station"))
        #expect(!names.contains("Asakusa Station"))
    }
}
