import AntipodesCore
import Foundation
import Testing

@Suite("Leg times and durations")
struct LegTimeTests {
    static func place(_ name: String, zone: String?, id: Int64) -> PlaceReference {
        PlaceReference(
            id: .database(.airport, id),
            kind: .airport,
            name: name,
            coordinate: Coordinate(latitude: 0, longitude: 0),
            timeZoneIdentifier: zone,
            code: name
        )
    }

    static let osl = place("OSL", zone: "Europe/Oslo", id: 1)
    static let jfk = place("JFK", zone: "America/New_York", id: 2)
    static let mystery = place("XXX", zone: nil, id: 3)

    static func time(_ iso: String) throws -> LocalDateTime {
        try #require(LocalDateTime(iso: iso))
    }

    @Test("Local date-times round-trip through their ISO form and reject nonsense")
    func parsing() throws {
        let time = try Self.time("2024-06-12T08:35")
        #expect(time.hour == 8)
        #expect(time.minute == 35)
        #expect(time.iso == "2024-06-12T08:35")
        #expect(LocalDateTime(iso: "2024-06-12T24:00") == nil)
        #expect(LocalDateTime(iso: "2024-06-12 08:35") == nil)
        #expect(LocalDateTime(iso: "2024-02-30T08:00") == nil)
    }

    /// Hand-computed: in June Oslo is UTC+2 and New York UTC−4. Departing 09:00 in Oslo
    /// is 07:00Z; arriving 11:30 in New York is 15:30Z; 8 h 30 m = 510 minutes. Reading
    /// both on one clock would say 150 minutes.
    @Test("A duration reads each end in its own zone")
    func durationAcrossZones() throws {
        let leg = try JourneyLeg(
            mode: .flight,
            origin: Self.osl,
            destination: Self.jfk,
            times: LegTimes(
                scheduledDeparture: Self.time("2024-06-12T09:00"),
                scheduledArrival: Self.time("2024-06-12T11:30")
            )
        )
        let duration = try leg.duration.get()
        #expect(duration.minutes == 510)
        #expect(duration.source == .scheduledTimes)
    }

    /// Daylight saving moves the offset: in January Oslo is UTC+1 and New York UTC−5,
    /// so the same wall clocks give 09:00+1 = 08:00Z to 11:30−5 = 16:30Z = 510 minutes
    /// again — the gap between the zones is six hours in both seasons.
    @Test("Daylight saving is honoured on both ends")
    func durationInWinter() throws {
        let leg = try JourneyLeg(
            mode: .flight,
            origin: Self.osl,
            destination: Self.jfk,
            times: LegTimes(
                scheduledDeparture: Self.time("2024-01-12T09:00"),
                scheduledArrival: Self.time("2024-01-12T11:30")
            )
        )
        #expect(leg.durationMinutes == 510)
    }

    @Test("Actual times win over scheduled ones, and an override wins over both")
    func durationPrecedence() throws {
        var leg = try JourneyLeg(
            mode: .flight,
            origin: Self.osl,
            destination: Self.jfk,
            times: LegTimes(
                scheduledDeparture: Self.time("2024-06-12T09:00"),
                scheduledArrival: Self.time("2024-06-12T11:30"),
                actualDeparture: Self.time("2024-06-12T09:20"),
                actualArrival: Self.time("2024-06-12T12:05")
            )
        )
        // 09:20+2 = 07:20Z to 12:05−4 = 16:05Z = 525 minutes.
        #expect(try leg.duration.get().minutes == 525)
        #expect(try leg.duration.get().source == .actualTimes)

        leg.durationMinutesOverride = 500
        #expect(try leg.duration.get().minutes == 500)
        #expect(try leg.duration.get().source == .userOverride)
    }

    @Test("No zone means no duration, rather than a wrong one")
    func missingZone() throws {
        let leg = try JourneyLeg(
            mode: .rail,
            origin: Self.osl,
            destination: Self.mystery,
            times: LegTimes(
                scheduledDeparture: Self.time("2024-06-12T09:00"),
                scheduledArrival: Self.time("2024-06-12T11:30")
            )
        )
        guard case let .failure(failure) = leg.duration else {
            Issue.record("expected no duration")
            return
        }
        #expect(failure.reason == .missingTimeZone)
        #expect(JourneyLeg(mode: .rail, origin: Self.osl, destination: Self.jfk)
            .durationMinutes == nil)
    }

    /// A delay compares two times at the same station, so it needs no zone at all.
    @Test("Delay is actual minus scheduled arrival, in minutes")
    func delay() throws {
        let times = try LegTimes(
            scheduledArrival: Self.time("2024-06-12T23:50"),
            actualArrival: Self.time("2024-06-13T00:25")
        )
        #expect(times.arrivalDelayMinutes == 35)
        let early = try LegTimes(
            scheduledArrival: Self.time("2024-06-12T10:00"),
            actualArrival: Self.time("2024-06-12T09:52")
        )
        #expect(early.arrivalDelayMinutes == -8)
    }

    /// Two legs through Oslo: arrive 10:15, depart 11:40, both on Oslo's clock — 85
    /// minutes, computed even without zones because both ends are the same place.
    @Test("Connections measure the change between legs, and carry the missed flag")
    func connections() throws {
        let bergen = Self.place("BGO", zone: nil, id: 4)
        let first = try JourneyLeg(
            mode: .flight,
            origin: bergen,
            destination: Self.mystery,
            times: LegTimes(scheduledArrival: Self.time("2024-06-12T10:15"))
        )
        let second = try JourneyLeg(
            mode: .flight,
            origin: Self.mystery,
            destination: Self.jfk,
            times: LegTimes(scheduledDeparture: Self.time("2024-06-12T11:40")),
            missedConnection: true
        )
        let journey = Journey(legs: [first, second])
        let connection = try #require(journey.connections.first)
        #expect(connection.minutes == 85)
        #expect(connection.isMissed)
        #expect(!connection.changesPlace)
    }

    @Test("A sleeper class or an arrival on a later day is overnight")
    func overnight() throws {
        let sleeper = JourneyLeg(
            mode: .rail,
            origin: Self.osl,
            destination: Self.jfk,
            travelClass: "Sleeper cabin"
        )
        #expect(sleeper.isOvernight)
        let night = try JourneyLeg(
            mode: .rail,
            origin: Self.osl,
            destination: Self.jfk,
            times: LegTimes(
                scheduledDeparture: Self.time("2024-06-12T22:00"),
                scheduledArrival: Self.time("2024-06-13T07:00")
            )
        )
        #expect(night.isOvernight)
        #expect(!JourneyLeg(mode: .rail, origin: Self.osl, destination: Self.jfk).isOvernight)
    }

    @Test("Riding again keeps the route and drops what was personal to the first ride")
    func rideAgain() throws {
        let original = try JourneyLeg(
            mode: .rail,
            origin: Self.osl,
            destination: Self.jfk,
            date: .year(2020),
            times: LegTimes(scheduledDeparture: Self.time("2020-01-01T08:00")),
            routeID: 1,
            operatorName: "Vy",
            seat: "12A",
            rating: 5,
            notes: "Snow"
        )
        let today = try #require(CalendarDate(year: 2024, month: 6, day: 1))
        let again = original.rideAgain(on: .day(today))
        #expect(again.id != original.id)
        #expect(again.date == .day(today))
        #expect(again.routeID == 1)
        #expect(again.operatorName == "Vy")
        #expect(again.seat == nil)
        #expect(again.rating == nil)
        #expect(again.notes == nil)
        #expect(again.times.isEmpty)
    }
}

@Suite("Calendar arithmetic")
struct CalendarArithmeticTests {
    @Test("Days since the epoch invert exactly, across leap days and centuries")
    func roundTrip() throws {
        for (year, month, day) in [
            (1970, 1, 1),
            (2000, 2, 29),
            (2024, 12, 31),
            (1900, 3, 1),
            (1600, 1, 1),
        ] {
            let date = try #require(CalendarDate(year: year, month: month, day: day))
            #expect(CalendarDate(daysSinceEpoch: date.daysSinceEpoch) == date)
        }
    }

    @Test("Adding days crosses month and leap-year boundaries")
    func adding() throws {
        let leap = try #require(CalendarDate(year: 2024, month: 2, day: 28))
        #expect(leap.adding(days: 1)?.iso == "2024-02-29")
        #expect(leap.adding(days: 2)?.iso == "2024-03-01")
        let newYear = try #require(CalendarDate(year: 2023, month: 12, day: 31))
        #expect(newYear.adding(days: 1)?.iso == "2024-01-01")
        #expect(newYear.adding(days: -365)?.iso == "2022-12-31")
    }
}

@Suite("Place implication")
struct PlaceImplicationTests {
    static let italy = PlaceReference(
        id: .database(.country, 920),
        kind: .country,
        name: "Italy",
        countryCode: "IT"
    )
    static let rome = PlaceReference(
        id: .database(.city, 3_169_070),
        kind: .city,
        name: "Rome",
        countryCode: "IT",
        regionCode: "IT.07"
    )
    static let lazio = PlaceReference(
        id: .database(.region, 3_174_976),
        kind: .region,
        name: "Lazio",
        countryCode: "IT",
        regionCode: "IT.07"
    )
    static let colosseum = PlaceReference(
        id: .database(.landmark, 10285),
        kind: .landmark,
        name: "Colosseum",
        countryCode: "IT",
        regionCode: "IT.07",
        cityID: 3_169_070,
        cityName: "Rome"
    )
    static let pantheon = PlaceReference(
        id: .database(.landmark, 99309),
        kind: .landmark,
        name: "Pantheon",
        countryCode: "IT",
        regionCode: "IT.07",
        cityID: 3_169_070
    )

    /// R-MODEL-6, and nothing wider.
    @Test("A landmark covers its city, region and country, and nothing beside them")
    func covers() {
        #expect(Self.colosseum.covers(Self.colosseum))
        #expect(Self.colosseum.covers(Self.rome))
        #expect(Self.colosseum.covers(Self.lazio))
        #expect(Self.colosseum.covers(Self.italy))
        #expect(!Self.colosseum.covers(Self.pantheon))
        #expect(!Self.rome.covers(Self.colosseum))
    }
}

@Suite("Emission factor lookup")
struct EmissionFactorTableTests {
    static let table = EmissionFactorTable(
        factors: [
            EmissionFactor(
                mode: .flight,
                kgCO2ePerKm: 0.14,
                basis: .passenger,
                label: "average",
                year: 2025
            ),
            EmissionFactor(
                mode: .flight,
                travelClass: "business",
                kgCO2ePerKm: 0.32,
                basis: .passenger,
                label: "business",
                year: 2025
            ),
            EmissionFactor(
                mode: .rail,
                kgCO2ePerKm: 0.035,
                basis: .passenger,
                label: "rail",
                year: 2025
            ),
        ],
        sourceName: "Test"
    )

    @Test("A class picks its own factor and falls back to the mode's average")
    func lookup() {
        #expect(Self.table.factor(for: .flight, travelClass: "Business class")?.kgCO2ePerKm == 0.32)
        #expect(Self.table.factor(for: .flight, travelClass: "Economy")?.kgCO2ePerKm == 0.14)
        #expect(Self.table.factor(for: .flight, travelClass: nil)?.kgCO2ePerKm == 0.14)
        #expect(Self.table.factor(for: .rail, travelClass: "First")?.kgCO2ePerKm == 0.035)
        #expect(Self.table.factor(for: .cableAndMountain, travelClass: nil) == nil)
        #expect(Self.table.factor(for: .humanPowered, travelClass: nil)?.kgCO2ePerKm == 0)
        #expect(Self.table.year == 2025)
    }
}

@Suite("Export compatibility")
struct CompatibilityTests {
    /// A leg exported by the M1 build has none of the v1 fields. It must still decode,
    /// or a user's own backup becomes unreadable.
    @Test("A leg without the v1 fields still decodes, with defaults")
    func legWithoutTimes() throws {
        let json = """
        {"id":"7B7C7A33-3F0B-4F1C-9C3A-2B1E8F2F0A11","mode":"flight",
         "origin":{"id":{"custom":{"_0":"7B7C7A33-3F0B-4F1C-9C3A-2B1E8F2F0A12"}},
                   "kind":"custom","name":"A"},
         "destination":{"id":{"custom":{"_0":"7B7C7A33-3F0B-4F1C-9C3A-2B1E8F2F0A13"}},
                        "kind":"custom","name":"B"},
         "date":{"value":"2024"},"purpose":"leisure"}
        """
        let leg = try JSONDecoder().decode(JourneyLeg.self, from: Data(json.utf8))
        #expect(leg.times.isEmpty)
        #expect(!leg.missedConnection)
        #expect(leg.routeID == nil)
        #expect(leg.date == .year(2024))
    }

    @Test("A log without a wishlist decodes with an empty one")
    func logWithoutWishlist() throws {
        let log = try JSONDecoder().decode(
            TravelLog.self,
            from: Data(#"{"trips":[],"visits":[],"journeys":[]}"#.utf8)
        )
        #expect(log.wishlist.isEmpty)
    }

    @Test("A leg with every v1 field survives a round trip")
    func roundTrip() throws {
        let leg = try JourneyLeg(
            mode: .rail,
            origin: LegTimeTests.osl,
            destination: LegTimeTests.jfk,
            date: .day(#require(CalendarDate(year: 2024, month: 6, day: 12))),
            times: LegTimes(scheduledDeparture: LegTimeTests.time("2024-06-12T09:00")),
            missedConnection: true,
            routeID: 7,
            routeName: "Tōkaidō Shinkansen",
            registration: "N12345"
        )
        let decoded = try JSONDecoder().decode(JourneyLeg.self, from: JSONEncoder().encode(leg))
        #expect(decoded == leg)
    }
}
