import Foundation

/// Lines on the Earth as lists of coordinates: cutting the stretch between two places
/// out of a longer line (R-PATH-1, R-TRAN-1).
public enum Polyline {
    /// Where a place falls on a line: the segment, how far along it, and how far off.
    struct Position {
        let segment: Int
        let fraction: Double
        let point: Coordinate
        let offKm: Double

        var index: Double {
            Double(segment) + fraction
        }
    }

    /// The stretch of `line` between the points nearest `start` and `end`, in the
    /// direction from one to the other, or nil if either is more than `toleranceKm`
    /// from it. A bus from Victoria to Oxford Circus is drawn along its route between
    /// the two stops, whichever way the route was drawn.
    public static func slice(
        _ line: [Coordinate],
        from start: Coordinate,
        to end: Coordinate,
        toleranceKm: Double = 1.5
    ) -> [Coordinate]? {
        guard line.count > 1,
              let first = position(of: start, on: line), first.offKm <= toleranceKm,
              let last = position(of: end, on: line), last.offKm <= toleranceKm
        else { return nil }
        if first.index <= last.index {
            return between(first, last, on: line)
        }
        return between(last, first, on: line).reversed()
    }

    /// The best slice among several lines — a route's directions and branches — by how
    /// close both places lie to it.
    public static func slice(
        among lines: [[Coordinate]],
        from start: Coordinate,
        to end: Coordinate,
        toleranceKm: Double = 1.5
    ) -> [Coordinate]? {
        var best: (path: [Coordinate], off: Double)?
        for line in lines {
            guard let a = position(of: start, on: line), let b = position(of: end, on: line),
                  a.offKm <= toleranceKm, b.offKm <= toleranceKm,
                  a.offKm + b.offKm < best?.off ?? .infinity,
                  let path = slice(line, from: start, to: end, toleranceKm: toleranceKm)
            else { continue }
            best = (path, a.offKm + b.offKm)
        }
        return best?.path
    }

    /// The indexes Douglas–Peucker keeps to stay within `toleranceKm` of a line; the
    /// ends always stay.
    public static func simplifiedIndices(_ line: [Coordinate], toleranceKm: Double) -> [Int] {
        guard line.count > 2 else { return Array(line.indices) }
        var keep = [Bool](repeating: false, count: line.count)
        keep[0] = true
        keep[line.count - 1] = true
        var stack = [(0, line.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }
            var worst = -1.0
            var index = first
            for i in (first + 1) ..< last {
                let (point, _) = TrackNetwork.closest(to: line[i], on: line[first], line[last])
                let off = GreatCircle.distanceKm(from: line[i], to: point)
                if off > worst {
                    worst = off
                    index = i
                }
            }
            if worst > toleranceKm {
                keep[index] = true
                stack.append((first, index))
                stack.append((index, last))
            }
        }
        return keep.indices.filter { keep[$0] }
    }

    static func position(of place: Coordinate, on line: [Coordinate]) -> Position? {
        var best: Position?
        for segment in 0 ..< max(0, line.count - 1) {
            let (point, fraction) = TrackNetwork.closest(
                to: place,
                on: line[segment],
                line[segment + 1]
            )
            let off = GreatCircle.distanceKm(from: place, to: point)
            if off < best?.offKm ?? .infinity {
                best = Position(segment: segment, fraction: fraction, point: point, offKm: off)
            }
        }
        return best
    }

    private static func between(
        _ a: Position,
        _ b: Position,
        on line: [Coordinate]
    ) -> [Coordinate] {
        var result = [a.point]
        if a.segment < b.segment {
            result += line[(a.segment + 1) ... b.segment]
        }
        result.append(b.point)
        return result.removingRepeats()
    }
}

/// Where a region's trail network lies (D-36), so only the one a leg is in is loaded.
public struct TrailRegion: Hashable, Sendable, Identifiable {
    /// The network's name in the route pack: `hiking/alps`.
    public let network: String
    public let kind: TrackKind
    public let name: String
    public let south: Double
    public let west: Double
    public let north: Double
    public let east: Double

    public var id: String {
        network
    }

    public init(
        network: String,
        kind: TrackKind,
        name: String,
        south: Double,
        west: Double,
        north: Double,
        east: Double
    ) {
        self.network = network
        self.kind = kind
        self.name = name
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        (south ... north).contains(coordinate.latitude)
            && (west ... east).contains(coordinate.longitude)
    }
}

/// A passenger aerial lift — a cable car, gondola or chair lift — from the route pack
/// (D-36), station to station.
public struct AerialLift: Hashable, Sendable, Identifiable {
    public let id: Int64
    /// OpenStreetMap's `aerialway` value: `cable_car`, `gondola`, `chair_lift`.
    public let kind: String
    public let name: String?
    public let startName: String?
    public let endName: String?
    public let lengthKm: Double
    /// From the start station to the end, simplified.
    public let points: [Coordinate]

    public init(
        id: Int64,
        kind: String,
        name: String?,
        startName: String?,
        endName: String?,
        lengthKm: Double,
        points: [Coordinate]
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.startName = startName
        self.endName = endName
        self.lengthKm = lengthKm
        self.points = points
    }

    public var start: Coordinate? {
        points.first
    }

    public var end: Coordinate? {
        points.last
    }

    /// "Gondola", "Chair lift".
    public var kindName: String {
        kind.replacingOccurrences(of: "_", with: " ").capitalized(with: nil)
            .replacingOccurrences(of: " Lift", with: " lift")
            .replacingOccurrences(of: " Car", with: " car")
    }

    /// How close two lifts' stations must be to be one junction.
    public static let stationMergeKm = 0.15

    /// Lifts as a network a cable-car leg is measured along (D-36): each lift an edge,
    /// each station a junction, and stations within ``stationMergeKm`` of each other one
    /// junction — the top of one gondola is where the next cable car leaves from.
    public static func network(_ lifts: [AerialLift], version: String) -> TrackNetwork {
        var nodes: [Coordinate] = []
        // Stations by a grid of about a kilometre, so a new one is compared only with
        // those around it.
        var nearby: [Int64: [Int]] = [:]
        func cell(_ latitude: Int64, _ longitude: Int64) -> Int64 {
            latitude * 1_000_000 + longitude
        }
        func node(_ point: Coordinate) -> Int {
            let row = Int64((point.latitude * 100).rounded(.down))
            let column = Int64((point.longitude * 100).rounded(.down))
            for dRow in -1 ... 1 {
                for dColumn in -1 ... 1 {
                    for index in nearby[cell(row + Int64(dRow), column + Int64(dColumn))] ?? []
                        where GreatCircle
                        .distanceKm(from: nodes[index], to: point) <= stationMergeKm {
                        return index
                    }
                }
            }
            nodes.append(point)
            nearby[cell(row, column), default: []].append(nodes.count - 1)
            return nodes.count - 1
        }
        let edges = lifts.compactMap { lift -> TrackEdge? in
            guard let start = lift.start, let end = lift.end,
                  lift.points.count > 1 else { return nil }
            return TrackEdge(
                a: node(start),
                b: node(end),
                lengthKm: lift.lengthKm,
                points: lift.points
            )
        }
        return TrackNetwork(kind: .lift, version: version, nodes: nodes, edges: edges)
    }
}
