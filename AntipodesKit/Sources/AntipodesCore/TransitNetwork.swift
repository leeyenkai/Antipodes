import Foundation

/// A city transit system (R-TRAN-1).
public struct TransitSystemInfo: Hashable, Sendable, Codable, Identifiable {
    public let id: Int64
    public let name: String
    public let kind: String
    public let cityName: String?
    public let countryCode: String
    /// The network the ride is logged against (R-TRAN-4).
    public let networkVersion: String

    public init(
        id: Int64,
        name: String,
        kind: String,
        cityName: String?,
        countryCode: String,
        networkVersion: String
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.cityName = cityName
        self.countryCode = countryCode
        self.networkVersion = networkVersion
    }
}

/// One line of a system.
public struct TransitLineInfo: Hashable, Sendable, Codable, Identifiable {
    public let id: Int64
    public let systemID: Int64
    public let name: String
    public let shortName: String?
    /// Six hex digits, where the network publishes the line's colour.
    public let colour: String?

    public init(id: Int64, systemID: Int64, name: String, shortName: String?, colour: String?) {
        self.id = id
        self.systemID = systemID
        self.name = name
        self.shortName = shortName
        self.colour = colour
    }
}

/// The stretch between two adjacent stops of a line (R-TRAN-2), the lower stop first,
/// so a ride either way covers the same segment.
public struct TransitSegment: Hashable, Sendable, Codable {
    public let lineID: Int64
    public let first: Int64
    public let second: Int64

    public init(lineID: Int64, between a: Int64, and b: Int64) {
        self.lineID = lineID
        first = min(a, b)
        second = max(a, b)
    }
}

/// A stop of a transit line.
public struct TransitStop: Hashable, Sendable, Codable, Identifiable {
    public let id: Int64
    public let name: String
    public let coordinate: Coordinate

    public init(id: Int64, name: String, coordinate: Coordinate) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}

/// The lines, stops and segments of the systems a log touches: what the transit stats
/// and the ride picker reason over. Pure, so routing is tested without a database.
public struct TransitNetwork: Hashable, Sendable {
    public var systems: [Int64: TransitSystemInfo]
    public var lines: [Int64: TransitLineInfo]
    public var stops: [Int64: TransitStop]
    /// Every segment, by line.
    public var segmentsByLine: [Int64: Set<TransitSegment>]

    public static let empty = TransitNetwork(systems: [:], lines: [:], stops: [:], segments: [])

    public init(
        systems: [Int64: TransitSystemInfo],
        lines: [Int64: TransitLineInfo],
        stops: [Int64: TransitStop],
        segments: [TransitSegment]
    ) {
        self.systems = systems
        self.lines = lines
        self.stops = stops
        segmentsByLine = Dictionary(grouping: segments, by: \.lineID).mapValues(Set.init)
    }

    public var isEmpty: Bool {
        systems.isEmpty
    }

    public func coordinate(of stop: Int64) -> Coordinate? {
        stops[stop]?.coordinate
    }

    /// Every segment of a system, across its lines: the whole network a percentage is
    /// measured against.
    public func segmentCount(ofSystem system: Int64) -> Int {
        lines.values.filter { $0.systemID == system }
            .reduce(0) { $0 + (segmentsByLine[$1.id]?.count ?? 0) }
    }

    /// The stops a ride on `line` passes, boarding to alighting inclusive, by the fewest
    /// segments; `nil` when the line's segments do not join the two (a gap in the data,
    /// or a stop not on the line).
    ///
    /// Breadth-first over the line's segments, neighbours visited in id order, so the
    /// same ride always takes the same way round a loop.
    public func route(onLine line: Int64, from start: Int64, to end: Int64) -> [Int64]? {
        guard let segments = segmentsByLine[line] else { return nil }
        if start == end {
            return segments.contains { $0.first == start || $0.second == start } ? [start] : nil
        }
        var neighbours: [Int64: [Int64]] = [:]
        for segment in segments {
            neighbours[segment.first, default: []].append(segment.second)
            neighbours[segment.second, default: []].append(segment.first)
        }
        guard neighbours[start] != nil, neighbours[end] != nil else { return nil }
        var previous: [Int64: Int64] = [start: start]
        var queue = [start]
        var index = 0
        while index < queue.count {
            let stop = queue[index]
            index += 1
            if stop == end {
                break
            }
            for next in (neighbours[stop] ?? []).sorted() where previous[next] == nil {
                previous[next] = stop
                queue.append(next)
            }
        }
        guard previous[end] != nil else { return nil }
        var path = [end]
        while let last = path.last, last != start, let before = previous[last] {
            path.append(before)
        }
        return path.reversed()
    }

    /// A line's stops in riding order, for the picker: walked from one end of the line —
    /// the lowest-id stop with a single neighbour, or the lowest-id stop of a loop — with
    /// branches after the trunk.
    public func orderedStops(ofLine line: Int64) -> [Int64] {
        guard let segments = segmentsByLine[line] else { return [] }
        var neighbours: [Int64: [Int64]] = [:]
        for segment in segments {
            neighbours[segment.first, default: []].append(segment.second)
            neighbours[segment.second, default: []].append(segment.first)
        }
        let ends = neighbours.filter { $0.value.count == 1 }.keys.sorted()
        var ordered: [Int64] = []
        var seen: Set<Int64> = []
        let starts = ends + neighbours.keys.sorted()
        for start in starts where !seen.contains(start) {
            var stack = [start]
            while let stop = stack.popLast() {
                guard seen.insert(stop).inserted else { continue }
                ordered.append(stop)
                // Reverse so the lowest id is walked first.
                for next in (neighbours[stop] ?? []).sorted().reversed()
                    where !seen.contains(next) {
                    stack.append(next)
                }
            }
        }
        return ordered
    }

    /// The length of a run of stops, stop to stop along great circles: the transit leg's
    /// stored path length (R-PATH-5).
    public func lengthKm(of stops: [Int64]) -> Double? {
        let points = stops.compactMap(coordinate(of:))
        guard points.count == stops.count, points.count > 1 else { return nil }
        return GreatCircle.pathLengthKm(points)
    }
}
