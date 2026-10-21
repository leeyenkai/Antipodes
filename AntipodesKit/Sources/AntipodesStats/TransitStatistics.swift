import AntipodesCore
import Foundation

/// How much of one line has been ridden.
public struct TransitLineCoverage: Hashable, Sendable, Identifiable {
    public var id: Int64 {
        line.id
    }

    public let line: TransitLineInfo
    public let segmentsRidden: Int
    public let segmentsTotal: Int

    public var fraction: Double {
        segmentsTotal == 0 ? 0 : Double(segmentsRidden) / Double(segmentsTotal)
    }
}

/// How much of one system has been ridden (§7, "% of each network ridden").
public struct TransitSystemCoverage: Hashable, Sendable, Identifiable {
    public var id: Int64 {
        system.id
    }

    public let system: TransitSystemInfo
    public let segmentsRidden: Int
    public let segmentsTotal: Int
    /// Every line of the system, ridden ones first.
    public let lines: [TransitLineCoverage]
    public let stationsVisited: Int
    public let rides: Int

    public var fraction: Double {
        segmentsTotal == 0 ? 0 : Double(segmentsRidden) / Double(segmentsTotal)
    }

    public var linesRidden: Int {
        lines.count { $0.segmentsRidden > 0 }
    }
}

/// City transit (§7, "City transit"; R-TRAN-2, R-TRAN-3): systems ridden, lines ridden,
/// stations visited three ways, and how much of each network.
///
/// Coverage is counted in segments — the stretch between two adjacent stops — so riding
/// the same stretch twice adds a ride but not coverage (R-TRAN-2). A ride's segments
/// come from its line's network: the fewest segments from where it boarded to where it
/// alighted. A ride logged between two places, not on a line, counts as a ride and
/// nothing more, and says so.
public struct TransitStatistics: Hashable, Sendable {
    /// City transit rides, linked to a line or not.
    public let rides: Int
    public let systems: [TransitSystemCoverage]
    public let boarded: Set<Int64>
    public let alighted: Set<Int64>
    /// Stops passed without getting on or off (R-TRAN-3).
    public let passedThrough: Set<Int64>
    /// Rides the coverage figures could use.
    public let input: StatInputSummary

    public var stationsVisited: Set<Int64> {
        boarded.union(alighted).union(passedThrough)
    }

    public var linesRidden: Int {
        systems.reduce(0) { $0 + $1.linesRidden }
    }

    public static let empty = TransitStatistics(
        rides: 0,
        systems: [],
        boarded: [],
        alighted: [],
        passedThrough: [],
        input: StatInputSummary()
    )

    public static func compute(
        for log: TravelLog,
        rules: CountingRules = .default,
        network: TransitNetwork
    ) -> TransitStatistics {
        var rides = 0
        var input = StatInputSummary()
        var boarded: Set<Int64> = []
        var alighted: Set<Int64> = []
        var passed: Set<Int64> = []
        var ridden: Set<TransitSegment> = []
        var ridesBySystem: [Int64: Int] = [:]
        var stopsBySystem: [Int64: Set<Int64>] = [:]

        for leg in log.allLegs where leg.mode == .cityTransit {
            guard rules.countsInStats(leg.purpose) else {
                input.exclude(.commuteExcluded)
                continue
            }
            rides += 1
            guard let lineID = leg.transitLineID, let line = network.lines[lineID],
                  case let .database(.station, start) = leg.origin.id,
                  case let .database(.station, end) = leg.destination.id
            else {
                input.exclude(.noTransitLine)
                continue
            }
            boarded.insert(start)
            alighted.insert(end)
            ridesBySystem[line.systemID, default: 0] += 1
            stopsBySystem[line.systemID, default: []].formUnion([start, end])
            guard let path = network.route(onLine: lineID, from: start, to: end) else {
                input.exclude(.transitRouteUnknown)
                continue
            }
            input.include()
            passed.formUnion(path.dropFirst().dropLast())
            stopsBySystem[line.systemID, default: []].formUnion(path)
            for (a, b) in zip(path, path.dropFirst()) {
                ridden.insert(TransitSegment(lineID: lineID, between: a, and: b))
            }
        }

        let systems = ridesBySystem.keys.compactMap { id in
            coverage(
                ofSystem: id,
                network: network,
                ridden: ridden,
                stations: stopsBySystem[id]?.count ?? 0,
                rides: ridesBySystem[id] ?? 0
            )
        }
        .sorted { ($0.fraction, $1.system.name) > ($1.fraction, $0.system.name) }

        return TransitStatistics(
            rides: rides,
            systems: systems,
            boarded: boarded,
            alighted: alighted,
            passedThrough: passed.subtracting(boarded).subtracting(alighted),
            input: input
        )
    }

    /// One system's share of segments ridden, line by line, ridden lines first.
    private static func coverage(
        ofSystem id: Int64,
        network: TransitNetwork,
        ridden: Set<TransitSegment>,
        stations: Int,
        rides: Int
    ) -> TransitSystemCoverage? {
        guard let system = network.systems[id] else { return nil }
        let lines = network.lines.values.filter { $0.systemID == id }.map { line in
            TransitLineCoverage(
                line: line,
                segmentsRidden: ridden.count { $0.lineID == line.id },
                segmentsTotal: network.segmentsByLine[line.id]?.count ?? 0
            )
        }
        .sorted { ($0.segmentsRidden > 0 ? 0 : 1, $0.line.name) < (
            $1.segmentsRidden > 0 ? 0 : 1,
            $1.line.name
        ) }
        return TransitSystemCoverage(
            system: system,
            segmentsRidden: lines.reduce(0) { $0 + $1.segmentsRidden },
            segmentsTotal: network.segmentCount(ofSystem: id),
            lines: lines,
            stationsVisited: stations,
            rides: rides
        )
    }
}
