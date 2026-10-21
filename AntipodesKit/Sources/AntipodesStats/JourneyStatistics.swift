import AntipodesCore
import Foundation

/// Totals across every journey that the distance family does not already cover (§5.7,
/// "Totals"): time spent by mode, the busiest travel day, the most varied journey, and
/// where the user has gone by land.
public struct JourneyStatistics: Hashable, Sendable {
    /// Minutes travelled, per mode, from legs with a known duration.
    public let minutesByMode: [TravelMode: Int]
    public let durationInput: StatInputSummary

    /// The day with the most legs on it.
    public let busiestDay: BusiestDay?
    /// Legs the busiest day could place: it needs the exact day.
    public let dayInput: StatInputSummary
    /// The journey that used the most different modes.
    public let mostVariedJourney: Journey?
    /// Countries reached overland: the ends of surface legs, every country a
    /// catalogue route ridden in full runs through — the Trans-Siberian crosses Russia
    /// and Mongolia whichever two cities it is logged between — and every country a
    /// rail leg's track runs through (R-PATH-6).
    public let countriesOverland: Set<String>
    /// Borders crossed on the ground: each change of country along a rail leg's track,
    /// or one for any other surface leg whose ends are in different countries.
    public let bordersCrossedOverland: Int
    /// Journeys with more than one leg, and how many connections were missed.
    public let multiLegJourneys: Int
    public let connectionsMissed: Int

    public var totalMinutes: Int {
        minutesByMode.values.reduce(0, +)
    }

    public var flightMinutes: Int {
        minutesByMode[.flight] ?? 0
    }

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        routes: [RouteInfo] = [],
        countriesAlong: [UUID: [String]] = [:]
    ) -> JourneyStatistics {
        let routesByID = routes.byID
        var minutes: [TravelMode: Int] = [:]
        var durationInput = StatInputSummary()
        var legsByDay: [CalendarDate: Int] = [:]
        var dayInput = StatInputSummary()
        var overland: Set<String> = []
        var borders = 0

        for leg in log.allLegs {
            guard rules.countsInStats(leg.purpose) else {
                durationInput.exclude(.commuteExcluded)
                continue
            }
            if let duration = leg.durationMinutes {
                durationInput.include()
                minutes[leg.mode, default: 0] += duration
            } else {
                durationInput.exclude(.timesUnavailable)
            }
            if case let .day(day) = leg.date {
                dayInput.include()
                legsByDay[day, default: 0] += 1
            } else {
                dayInput.exclude(leg.date.isKnown ? .datePrecisionTooLow : .unknownDate)
            }
            if leg.mode != .flight {
                for code in [leg.origin.countryCode, leg.destination.countryCode]
                    .compactMap(\.self) {
                    overland.insert(code)
                }
                if let route = leg.routeID.flatMap({ routesByID[$0] }),
                   route.isRiddenInFull(by: leg) {
                    overland.formUnion(route.countryCodes)
                }
                borders += crossings(of: leg, along: countriesAlong, into: &overland)
            }
        }

        let counted = log.journeys.filter { journey in
            journey.legs.contains { rules.countsInStats($0.purpose) }
        }
        let busiest = legsByDay
            .max { ($0.value, $1.key) < ($1.value, $0.key) }
            .flatMap { $0.value > 1 ? BusiestDay(day: $0.key, legs: $0.value) : nil }

        return JourneyStatistics(
            minutesByMode: minutes,
            durationInput: durationInput,
            busiestDay: busiest,
            dayInput: dayInput,
            mostVariedJourney: counted
                .filter { $0.modes.count > 1 }
                .max { ($0.modes.count, $0.legs.count) < ($1.modes.count, $1.legs.count) },
            countriesOverland: overland,
            bordersCrossedOverland: borders,
            multiLegJourneys: counted.count { $0.legs.count > 1 },
            connectionsMissed: counted.reduce(0) { $0 + $1.connections.count(where: \.isMissed) }
        )
    }
}

public struct BusiestDay: Hashable, Sendable {
    public let day: CalendarDate
    public let legs: Int

    public init(day: CalendarDate, legs: Int) {
        self.day = day
        self.legs = legs
    }
}

extension JourneyStatistics {
    /// The borders a surface leg crossed, adding the countries it ran through: each
    /// change of country along its track where the railway map gave it one (R-PATH-6),
    /// or one border when its two ends are in different countries.
    static func crossings(
        of leg: JourneyLeg,
        along countries: [UUID: [String]],
        into set: inout Set<String>
    ) -> Int {
        if let along = countries[leg.id], !along.isEmpty {
            set.formUnion(along)
            return along.count - 1
        }
        if let from = leg.origin.countryCode, let to = leg.destination.countryCode, from != to {
            return 1
        }
        return 0
    }
}

/// The rail group of the journey stats (§5.7, "Rail").
///
/// Stations are the ends of rail legs as logged — cities or custom pins, since the
/// bundled database has no list of main-line stations (D-8). The railway map (D-30)
/// has track but no stations, so stations passed through are not attempted; it does
/// say which countries a leg's track runs through (R-PATH-6).
public struct RailStatistics: Hashable, Sendable {
    public let legCount: Int
    public let kilometres: Double
    /// Rail legs the kilometres could use: a leg with no distance adds nothing.
    public let kilometreInput: StatInputSummary
    public let operators: Set<String>
    public let classes: Set<String>
    public let trainTypes: Set<String>
    /// Catalogue routes ridden (R-JLOG-3).
    public let namedServices: Set<String>
    public let stations: Set<PlaceID>
    /// Rail legs that were sleepers or ran overnight.
    public let overnightLegs: Int
    /// The ends' countries, a full catalogue route's, and those along the track.
    public let countries: Set<String>
    public let bordersCrossed: Int
    /// The highest point of any catalogue route ridden in full, where the catalogue has
    /// one. A section of a route may not pass its summit.
    public let highestPointM: Double?
    public let input: StatInputSummary

    // One pass over the rail legs tallies every figure.
    // swiftlint:disable function_body_length
    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        routes: [RouteInfo] = [],
        countriesAlong: [UUID: [String]] = [:]
    ) -> RailStatistics {
        var legCount = 0
        var kilometres = 0.0
        var operators: Set<String> = []
        var classes: Set<String> = []
        var types: Set<String> = []
        var named: Set<String> = []
        var stations: Set<PlaceID> = []
        var overnight = 0
        var countries: Set<String> = []
        var borders = 0
        var highest: Double?
        var input = StatInputSummary()
        var kilometreInput = StatInputSummary()
        let routesByID = routes.byID

        for leg in log.allLegs where leg.mode == .rail {
            guard rules.countsInStats(leg.purpose) else {
                input.exclude(.commuteExcluded)
                continue
            }
            input.include()
            legCount += 1
            if leg.distanceSource != .unavailable {
                kilometreInput.include()
                kilometres += leg.distanceKm
            } else {
                kilometreInput.exclude(.distanceUnavailable)
            }
            if let value = leg.operatorName?.nonEmpty {
                operators.insert(value)
            }
            if let value = leg.travelClass?.nonEmpty {
                classes.insert(value)
            }
            if let value = leg.vehicle?.nonEmpty {
                types.insert(value)
            }
            if let name = leg.routeName?.nonEmpty ?? leg.routeID.flatMap({ routesByID[$0]?.name }) {
                named.insert(name)
            }
            if let route = leg.routeID.flatMap({ routesByID[$0] }),
               route.isRiddenInFull(by: leg),
               let point = route.highestPointM {
                highest = max(highest ?? point, point)
            }
            stations.insert(leg.origin.id)
            stations.insert(leg.destination.id)
            if leg.isOvernight {
                overnight += 1
            }
            for code in [leg.origin.countryCode, leg.destination.countryCode].compactMap(\.self) {
                countries.insert(code)
            }
            if let route = leg.routeID.flatMap({ routesByID[$0] }), route.isRiddenInFull(by: leg) {
                countries.formUnion(route.countryCodes)
            }
            borders += JourneyStatistics.crossings(of: leg, along: countriesAlong, into: &countries)
        }

        return RailStatistics(
            legCount: legCount,
            kilometres: kilometres,
            kilometreInput: kilometreInput,
            operators: operators,
            classes: classes,
            trainTypes: types,
            namedServices: named,
            stations: stations,
            overnightLegs: overnight,
            countries: countries,
            bordersCrossed: borders,
            highestPointM: highest,
            input: input
        )
    }
    // swiftlint:enable function_body_length
}

/// How late things ran (§5.7, "Punctuality"). Delay is actual minus scheduled arrival,
/// from times the user entered by hand (R-JLOG-8).
public struct PunctualityStatistics: Hashable, Sendable {
    public struct OperatorRecord: Hashable, Sendable, Identifiable {
        public var id: String {
            name
        }

        public let name: String
        public let legs: Int
        public let averageDelayMinutes: Double
    }

    /// A leg counts as on time up to this many minutes late — the common threshold for
    /// flights, applied to every mode so the figures compare.
    public static let onTimeToleranceMinutes = 15

    public let averageDelayMinutes: Double?
    public let averageDelayByMode: [TravelMode: Double]
    public let operators: [OperatorRecord]
    public let onTimeShare: Double?
    public let worstDelay: JourneyLeg?
    public let worstDelayMinutes: Int?
    public let input: StatInputSummary

    /// Needs at least this many timed legs before an operator is ranked, so one late
    /// train does not make an operator "least punctual".
    public static let minimumLegsToRank = 2

    public var mostPunctualOperator: OperatorRecord? {
        operators
            .filter { $0.legs >= Self.minimumLegsToRank }
            .min { ($0.averageDelayMinutes, $0.name) < ($1.averageDelayMinutes, $1.name) }
    }

    public var leastPunctualOperator: OperatorRecord? {
        operators
            .filter { $0.legs >= Self.minimumLegsToRank }
            .max { ($0.averageDelayMinutes, $1.name) < ($1.averageDelayMinutes, $0.name) }
    }

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default
    ) -> PunctualityStatistics {
        var delays: [Int] = []
        var byMode: [TravelMode: [Int]] = [:]
        var byOperator: [String: [Int]] = [:]
        var worst: (JourneyLeg, Int)?
        var input = StatInputSummary()

        for leg in log.allLegs where leg.mode.isScheduledService {
            guard rules.countsInStats(leg.purpose) else {
                input.exclude(.commuteExcluded)
                continue
            }
            guard let delay = leg.times.arrivalDelayMinutes else {
                input.exclude(.timesUnavailable)
                continue
            }
            input.include()
            delays.append(delay)
            byMode[leg.mode, default: []].append(delay)
            if let name = leg.operatorName?.nonEmpty {
                byOperator[name, default: []].append(delay)
            }
            if delay > (worst?.1 ?? 0) {
                worst = (leg, delay)
            }
        }

        let average: ([Int]) -> Double? = { values in
            Summary.mean(values.map(Double.init))
        }
        return PunctualityStatistics(
            averageDelayMinutes: average(delays),
            averageDelayByMode: byMode.compactMapValues(average),
            operators: byOperator
                .map { OperatorRecord(
                    name: $0.key,
                    legs: $0.value.count,
                    averageDelayMinutes: average($0.value) ?? 0
                ) }
                .sorted { $0.name < $1.name },
            onTimeShare: delays.isEmpty
                ? nil
                : Double(delays.count { $0 <= onTimeToleranceMinutes }) / Double(delays.count),
            worstDelay: worst?.0,
            worstDelayMinutes: worst?.1,
            input: input
        )
    }
}

/// Estimated carbon (§5.7, "Carbon", R-CO2-1 to R-CO2-3).
///
/// Every figure here is an estimate and is shown as one, with the publisher and year
/// of the factors. A leg's estimate is its distance times the factor for its mode and
/// class; a ground leg's saving is what flying the same two ends would have emitted,
/// using the great-circle distance and the average flight factor, minus its own.
public struct CarbonStatistics: Hashable, Sendable {
    public let totalKg: Double
    public let kgByLeg: [UUID: Double]
    public let kgByMode: [TravelMode: Double]
    public let kgByYear: [Int: Double]
    public let kgByTrip: [UUID: Double]
    /// Kilograms a ground leg saved against flying the same two ends, per leg. Can be
    /// negative: a long solo drive can emit more than the flight.
    public let savedByLeg: [UUID: Double]
    /// Legs whose factor is per vehicle rather than per passenger — the whole car.
    public let vehicleBasisLegs: Int
    public let factorYear: Int?
    public let sourceName: String
    public let input: StatInputSummary

    public var totalSavedKg: Double {
        savedByLeg.values.reduce(0, +)
    }

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        factors: EmissionFactorTable
    ) -> CarbonStatistics {
        var total = 0.0
        var byLeg: [UUID: Double] = [:]
        var byMode: [TravelMode: Double] = [:]
        var byYear: [Int: Double] = [:]
        var byTrip: [UUID: Double] = [:]
        var saved: [UUID: Double] = [:]
        var vehicleLegs = 0
        var input = StatInputSummary()
        let comparison = factors.factor(for: .flight, travelClass: nil)

        for journey in log.journeys {
            for leg in journey.legs {
                guard rules.countsInStats(leg.purpose) else {
                    input.exclude(.commuteExcluded)
                    continue
                }
                guard leg.distanceSource != .unavailable else {
                    input.exclude(.distanceUnavailable)
                    continue
                }
                // A road trip's class is the vehicle — car or motorbike — so that is
                // what picks its factor.
                let classText = leg.mode == .roadTrip ? leg.vehicle ?? leg.travelClass : leg
                    .travelClass
                guard let factor = factors.factor(for: leg.mode, travelClass: classText) else {
                    input.exclude(.noEmissionFactor)
                    continue
                }
                input.include()
                let kilograms = leg.distanceKm * factor.kgCO2ePerKm
                total += kilograms
                byLeg[leg.id] = kilograms
                byMode[leg.mode, default: 0] += kilograms
                if let year = leg.date.year {
                    byYear[year, default: 0] += kilograms
                }
                if let trip = journey.tripID {
                    byTrip[trip, default: 0] += kilograms
                }
                if factor.basis == .vehicle {
                    vehicleLegs += 1
                }
                if leg.mode != .flight, let comparison, let direct = leg.greatCircleKm {
                    saved[leg.id] = direct * comparison.kgCO2ePerKm - kilograms
                }
            }
        }

        return CarbonStatistics(
            totalKg: total,
            kgByLeg: byLeg,
            kgByMode: byMode,
            kgByYear: byYear,
            kgByTrip: byTrip,
            savedByLeg: saved,
            vehicleBasisLegs: vehicleLegs,
            factorYear: factors.year,
            sourceName: factors.sourceName,
            input: input
        )
    }
}

extension String {
    /// `nil` for an empty or whitespace-only string.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension [RouteInfo] {
    /// The routes by id; a duplicate id keeps the first.
    var byID: [Int64: RouteInfo] {
        Dictionary(map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
