import AntipodesCore
import AntipodesStats
import Foundation
import Testing

@Suite("Temperature in the month visited and climate zones")
struct ClimateStatisticsTests {
    /// Oslo's normals, January first; they sum to 71, so the annual mean is 71 / 12.
    static let osloMonths: [Double] = [-4, -4, 0, 5, 11, 15, 17, 16, 11, 6, 1, -3]
    static let oslo = PlaceReference(
        id: .database(.city, 10),
        kind: .city,
        name: "Oslo",
        countryCode: "NO"
    )
    /// A landmark in Oslo with no climate row of its own: it takes its city's.
    static let vigeland = PlaceReference(
        id: .database(.landmark, 30),
        kind: .landmark,
        name: "Vigeland Park",
        countryCode: "NO",
        cityID: 10
    )
    static let pin = PlaceReference(id: .custom(UUID()), kind: .custom, name: "Somewhere")
    static let gazetteer = Gazetteer(places: [
        oslo.id: PlaceFacts(monthlyMeanTemperatureC: osloMonths, koppen: "Dfb"),
    ])

    static func day(_ iso: String) -> CalendarDate {
        CalendarDate(iso: iso)!
    }

    /// Oslo on 12 July: 17. Oslo in January 2023: −4. Vigeland 28 June to 3 July:
    /// three days at June's 15 and three at July's 17, (45 + 51) / 6 = 16. Oslo in 2019:
    /// the annual mean 71 / 12 ≈ 5.917, flagged. An undated visit and a pin with no
    /// climate are left out. Average (17 − 4 + 16 + 5.917) / 4 ≈ 8.729.
    @Test("Each visit takes its month's normal; ranges weigh by day; years take the mean")
    func temperatures() {
        let log = TravelLog(visits: [
            Visit(place: Self.oslo, date: .day(Self.day("2024-07-12"))),
            Visit(place: Self.oslo, date: .month(year: 2023, month: 1)),
            Visit(
                place: Self.vigeland,
                date: .range(start: Self.day("2022-06-28"), end: Self.day("2022-07-03"))
            ),
            Visit(place: Self.oslo, date: .year(2019)),
            Visit(place: Self.oslo, date: .unknown),
            Visit(place: Self.pin, date: .day(Self.day("2024-01-01"))),
        ])
        let stats = ClimateStatistics.compute(for: log, gazetteer: Self.gazetteer)
        #expect(abs((stats.averageTemperatureC ?? 0) - 8.729) < 0.001)
        #expect(stats.hottest?.temperatureC == 17)
        #expect(stats.coldest?.temperatureC == -4)
        #expect(stats.visits.count == 4)
        #expect(stats.annualMeanCount == 1)
        #expect(stats.temperatureInput.used == 4)
        #expect(stats.temperatureInput.exclusions[.unknownDate] == 1)
        #expect(stats.temperatureInput.exclusions[.attributeUnknown] == 1)
        let range = stats.visits.first { $0.place.name == "Vigeland Park" }
        #expect(range?.temperatureC == 16)
    }

    /// Oslo and Vigeland (by its city) are both Dfb; the pin has no zone. Places count
    /// once however often they were visited.
    @Test("Climate zones gather each place once")
    func zones() throws {
        let log = TravelLog(visits: [
            Visit(place: Self.oslo, date: .year(2019)),
            Visit(place: Self.oslo, date: .year(2020)),
            Visit(place: Self.vigeland),
            Visit(place: Self.pin),
        ])
        let stats = ClimateStatistics.compute(for: log, gazetteer: Self.gazetteer)
        let zone = try #require(ClimateZone(code: "Dfb"))
        #expect(stats.zones == [zone])
        #expect(stats.placesByZone[zone]?.map(\.name) == ["Oslo", "Vigeland Park"])
        #expect(stats.groups == [.continental])
        #expect(stats.zoneInput.used == 2)
        #expect(stats.zoneInput.excludedCount == 1)
    }

    @Test("Zone codes have names and groups; unknown codes are refused")
    func zoneNames() {
        #expect(ClimateZone(code: "Cfb")?.name == "Temperate oceanic")
        #expect(ClimateZone(code: "BWh")?.group == .arid)
        #expect(ClimateZone(code: "Zz") == nil)
    }
}
