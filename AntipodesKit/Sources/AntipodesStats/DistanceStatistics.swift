import AntipodesCore
import Foundation

/// How far the user has travelled: the distance and routes family (§7, §5.7).
///
/// Distances come from each leg's resolved path, never re-derived here, so these
/// totals always agree with what the globe draws (R-PATH-5).
public struct DistanceStatistics: Hashable, Sendable {
    public let totalKm: Double
    public let kilometresByMode: [TravelMode: Double]
    public let legCountByMode: [TravelMode: Int]

    /// Legs whose distance is a straight-line stand-in for a real surface path. Shown
    /// so the user knows which part of the total is soft (R-PATH-3).
    public let approximateLegCount: Int
    public let approximateKm: Double

    public let longestLeg: JourneyLeg?
    public let longestJourney: Journey?
    public let input: StatInputSummary

    /// Total distance as a multiple of the Earth's circumference.
    public var timesRoundTheEarth: Double {
        totalKm / GreatCircle.equatorialCircumferenceKm
    }

    public var legCount: Int {
        legCountByMode.values.reduce(0, +)
    }

    /// Fraction of the total that rests on an approximated path, in 0...1.
    public var approximateFraction: Double {
        totalKm == 0 ? 0 : approximateKm / totalKm
    }

    public var modesSortedByDistance: [(mode: TravelMode, kilometres: Double)] {
        kilometresByMode
            .map { (mode: $0.key, kilometres: $0.value) }
            .sorted { ($0.kilometres, $0.mode.rawValue) > ($1.kilometres, $1.mode.rawValue) }
    }

    public func totalDistance(in system: UnitSystem) -> Double {
        system.distance(fromKilometres: totalKm)
    }

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default
    ) -> DistanceStatistics {
        var totalKm = 0.0
        var kilometresByMode: [TravelMode: Double] = [:]
        var legCountByMode: [TravelMode: Int] = [:]
        var approximateLegCount = 0
        var approximateKm = 0.0
        var longestLeg: JourneyLeg?
        var input = StatInputSummary()

        for leg in log.allLegs {
            guard rules.countsInStats(leg.purpose) else {
                input.exclude(.commuteExcluded)
                continue
            }
            let (kilometres, source) = leg.distance
            guard source != .unavailable else {
                input.exclude(.distanceUnavailable)
                continue
            }
            input.include()

            totalKm += kilometres
            kilometresByMode[leg.mode, default: 0] += kilometres
            legCountByMode[leg.mode, default: 0] += 1

            if source.isApproximate {
                approximateLegCount += 1
                approximateKm += kilometres
            }
            if kilometres > (longestLeg?.distanceKm ?? -1) {
                longestLeg = leg
            }
        }

        let countedJourneys = log.journeys.filter { journey in
            journey.legs.contains { rules.countsInStats($0.purpose) }
        }

        return DistanceStatistics(
            totalKm: totalKm,
            kilometresByMode: kilometresByMode,
            legCountByMode: legCountByMode,
            approximateLegCount: approximateLegCount,
            approximateKm: approximateKm,
            longestLeg: longestLeg,
            longestJourney: countedJourneys.max { $0.totalDistanceKm < $1.totalDistanceKm },
            input: input
        )
    }
}

/// Flight-specific totals, the part of the distance family that lands in M1.
public struct FlightStatistics: Hashable, Sendable {
    /// Every flight counted in stats, with or without a distance — the same flights
    /// the "Flights" badges count.
    public let flightCount: Int
    /// Flights the distance figures could use.
    public let measuredFlightCount: Int
    public let totalKm: Double
    public let airportIDs: Set<PlaceID>
    public let airlineNames: Set<String>
    public let aircraftTypes: Set<String>
    public let longestFlight: JourneyLeg?
    public let input: StatInputSummary

    public var airportsVisited: Int {
        airportIDs.count
    }

    public var averageFlightKm: Double {
        measuredFlightCount == 0 ? 0 : totalKm / Double(measuredFlightCount)
    }

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default
    ) -> FlightStatistics {
        var flightCount = 0
        var measuredFlightCount = 0
        var totalKm = 0.0
        var airportIDs: Set<PlaceID> = []
        var airlineNames: Set<String> = []
        var aircraftTypes: Set<String> = []
        var longestFlight: JourneyLeg?
        var input = StatInputSummary()

        for leg in log.allLegs where leg.mode == .flight {
            guard rules.countsInStats(leg.purpose) else {
                input.exclude(.commuteExcluded)
                continue
            }
            flightCount += 1
            if leg.origin.kind == .airport {
                airportIDs.insert(leg.origin.id)
            }
            if leg.destination.kind == .airport {
                airportIDs.insert(leg.destination.id)
            }
            if let airline = leg.operatorName, !airline.isEmpty {
                airlineNames.insert(airline)
            }
            if let aircraft = leg.vehicle, !aircraft.isEmpty {
                aircraftTypes.insert(aircraft)
            }
            let (kilometres, source) = leg.distance
            guard source != .unavailable else {
                input.exclude(.distanceUnavailable)
                continue
            }
            input.include()
            measuredFlightCount += 1
            totalKm += kilometres
            if kilometres > (longestFlight?.distanceKm ?? -1) {
                longestFlight = leg
            }
        }

        return FlightStatistics(
            flightCount: flightCount,
            measuredFlightCount: measuredFlightCount,
            totalKm: totalKm,
            airportIDs: airportIDs,
            airlineNames: airlineNames,
            aircraftTypes: aircraftTypes,
            longestFlight: longestFlight,
            input: input
        )
    }
}
