import AntipodesCore
import Foundation

/// The road and sea group of the journey stats (§5.7, "Road and sea"): distance driven,
/// ferries taken, the longest sea crossing and the ships sailed on.
///
/// Mountain passes count the passes the user logged — a visit of any type to a place
/// the database calls a mountain pass — since a leg's line is straight until path
/// snapping exists and cannot say which pass a road went over (R-PATH-1).
public struct RoadAndSeaStatistics: Hashable, Sendable {
    /// The landmark kind the database gives a mountain pass.
    public static let passKind = "mountain pass"

    /// Road-trip legs — the user's own car or motorbike — and the distance they cover.
    public let roadTripLegs: Int
    public let kilometresDriven: Double
    /// Road trips the distance could use: a leg with no distance adds nothing.
    public let roadInput: StatInputSummary

    public let ferriesTaken: Int
    public let seaKilometres: Double
    public let longestSeaCrossing: JourneyLeg?
    /// Ships by name where one was given, otherwise by the kind of ship.
    public let ships: Set<String>
    public let ferryOperators: Set<String>
    /// Ferries the distances could use.
    public let seaInput: StatInputSummary
    /// Mountain passes visited, each once, and the visits behind them.
    public let passes: [PlaceReference]
    public let passVisitIDs: [UUID]

    // One pass over the road and sea legs tallies every figure.
    // swiftlint:disable:next function_body_length
    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        gazetteer: Gazetteer = .empty
    ) -> RoadAndSeaStatistics {
        let (passes, passVisits) = Self.passes(in: log, gazetteer: gazetteer)
        var roadLegs = 0
        var driven = 0.0
        var roadInput = StatInputSummary()
        var ferries = 0
        var sea = 0.0
        var longest: JourneyLeg?
        var ships: Set<String> = []
        var operators: Set<String> = []
        var seaInput = StatInputSummary()

        for leg in log.allLegs where leg.mode == .roadTrip || leg.mode == .ferry {
            let isRoad = leg.mode == .roadTrip
            guard rules.countsInStats(leg.purpose) else {
                if isRoad {
                    roadInput.exclude(.commuteExcluded)
                } else {
                    seaInput.exclude(.commuteExcluded)
                }
                continue
            }
            let measured = leg.distanceSource != .unavailable
            if isRoad {
                roadLegs += 1
                guard measured else {
                    roadInput.exclude(.distanceUnavailable)
                    continue
                }
                roadInput.include()
                driven += leg.distanceKm
            } else {
                ferries += 1
                if let ship = leg.registration?.nonEmpty ?? leg.vehicle?.nonEmpty {
                    ships.insert(ship)
                }
                if let name = leg.operatorName?.nonEmpty {
                    operators.insert(name)
                }
                guard measured else {
                    seaInput.exclude(.distanceUnavailable)
                    continue
                }
                seaInput.include()
                sea += leg.distanceKm
                if leg.distanceKm > (longest?.distanceKm ?? -1) {
                    longest = leg
                }
            }
        }

        return RoadAndSeaStatistics(
            roadTripLegs: roadLegs,
            kilometresDriven: driven,
            roadInput: roadInput,
            ferriesTaken: ferries,
            seaKilometres: sea,
            longestSeaCrossing: longest,
            ships: ships,
            ferryOperators: operators,
            seaInput: seaInput,
            passes: passes,
            passVisitIDs: passVisits.map(\.id)
        )
    }

    /// Mountain passes visited, earliest first and each once, and every visit to one.
    private static func passes(
        in log: TravelLog,
        gazetteer: Gazetteer
    ) -> ([PlaceReference], [Visit]) {
        let visits = log.visits.filter {
            gazetteer.facts(for: $0.place.id)?.landmarkKind == passKind
        }
        var seen: Set<PlaceID> = []
        let passes = visits
            .sorted { $0.date < $1.date }
            .map(\.place)
            .filter { seen.insert($0.id).inserted }
        return (passes, visits)
    }
}
