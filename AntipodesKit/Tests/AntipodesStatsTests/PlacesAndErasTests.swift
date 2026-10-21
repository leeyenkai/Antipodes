import AntipodesCore
import AntipodesStats
import Foundation
import Testing

@Suite("Mountain passes, nightlife and landmark eras")
struct PlacesAndErasTests {
    static func landmark(_ name: String, id: Int64) -> PlaceReference {
        PlaceReference(id: .database(.landmark, id), kind: .landmark, name: name, countryCode: "CH")
    }

    static let stelvio = landmark("Stelvio Pass", id: 1)
    static let gotthard = landmark("Gotthard Pass", id: 2)
    static let castle = landmark("Castle", id: 3)
    static let passFacts = PlaceFacts(themes: ["nature"], landmarkKind: "mountain pass")

    /// Stelvio passed through twice and Gotthard once, with a castle that is not a
    /// pass: two passes, three visits behind them. "Passed through" does not count
    /// towards coverage, but crossing a pass is exactly passing through it.
    @Test("Mountain passes count every visit to a pass, each pass once")
    func passes() {
        let gazetteer = Gazetteer(places: [
            Self.stelvio.id: Self.passFacts,
            Self.gotthard.id: Self.passFacts,
            Self.castle.id: PlaceFacts(landmarkKind: "castle"),
        ])
        let log = TravelLog(visits: [
            Visit(place: Self.stelvio, visitType: .passedThrough, date: .year(2021)),
            Visit(place: Self.stelvio, visitType: .passedThrough, date: .year(2023)),
            Visit(place: Self.gotthard, visitType: .passedThrough, date: .year(2022)),
            Visit(place: Self.castle, date: .year(2022)),
        ])
        let stats = RoadAndSeaStatistics.compute(for: log, gazetteer: gazetteer)
        #expect(stats.passes.map(\.name) == ["Stelvio Pass", "Gotthard Pass"])
        #expect(stats.passVisitIDs.count == 3)

        let badge = AchievementDefinition(
            id: "passes",
            name: "Passes",
            description: "",
            rule: .mountainPasses,
            threshold: 2
        )
        let status = AchievementEngine.evaluate([badge], log: log, gazetteer: gazetteer)
        #expect(status.first?.isEarned == true)
    }

    /// Oslo is continental (Dfb) and Rome temperate (Csa): two of the five climates.
    @Test("Climate groups count the main climates reached")
    func climateGroups() {
        let oslo = PlaceReference(id: .database(.city, 10), kind: .city, name: "Oslo")
        let rome = PlaceReference(id: .database(.city, 11), kind: .city, name: "Rome")
        let gazetteer = Gazetteer(places: [
            oslo.id: PlaceFacts(koppen: "Dfb"),
            rome.id: PlaceFacts(koppen: "Csa"),
        ])
        let log = TravelLog(visits: [Visit(place: oslo), Visit(place: rome)])
        let badge = AchievementDefinition(
            id: "climates",
            name: "Climates",
            description: "",
            rule: .climateGroups,
            threshold: 3
        )
        let status = AchievementEngine.evaluate([badge], log: log, gazetteer: gazetteer)
        #expect(status.first?.current == 2)
        #expect(status.first?.isEarned == false)
    }

    /// Century n covers the hundred years from (n − 1) × 100; BC runs the other way.
    @Test("An era's years are read from its wording")
    func eraYears() {
        #expect(PlaceFacts(era: "15th century").eraYears == 1400 ... 1499)
        #expect(PlaceFacts(era: "5th century BC").eraYears == -500 ... -401)
        #expect(PlaceFacts(era: "2nd millennium").eraYears == 1000 ... 1999)
        #expect(PlaceFacts(era: "3rd millennium BC").eraYears == -3000 ... -2001)
        #expect(PlaceFacts(era: "Roman").eraYears == nil)
    }

    /// The 15th century (1400–1499) is medieval throughout; the 5th century BC is
    /// ancient; the 2nd millennium runs from medieval to modern, so says nothing.
    @Test("An era places a landmark only when it lies within one historical era")
    func historicalEra() {
        #expect(HistoricalEra.of(PlaceFacts(era: "15th century")) == .medieval)
        #expect(HistoricalEra.of(PlaceFacts(era: "5th century BC")) == .ancient)
        #expect(HistoricalEra.of(PlaceFacts(era: "2nd millennium")) == nil)
        #expect(HistoricalEra.of(PlaceFacts(yearBuilt: 1889, era: "2nd millennium")) == .industrial)
    }

    /// Four nightlife districts and two museums: nightlife holds 4 of 6, past the
    /// Night owl's 20 %, while art and museums hold 2 of 6, under the Aesthete's 40 %.
    @Test("A mix heavy on nightlife reads as a Night owl")
    func nightOwl() throws {
        var gazetteer = Gazetteer()
        var visits: [Visit] = []
        let nightlife = Array(repeating: ["nightlife"], count: 4)
        let mix = nightlife + Array(repeating: ["art-and-museums"], count: 2)
        for (index, themes) in mix.enumerated() {
            let place = Self.landmark("L\(index)", id: Int64(100 + index))
            gazetteer.places[place.id] = PlaceFacts(themes: themes)
            visits.append(Visit(place: place))
        }
        let stats = ThemeStatistics.compute(for: TravelLog(visits: visits), gazetteer: gazetteer)
        #expect(try #require(stats.personality).archetype == .nightOwl)
    }
}
