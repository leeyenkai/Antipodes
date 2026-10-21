import Foundation

/// A stretch of track, road or sea lane between two junctions of a ``TrackNetwork``.
public struct TrackEdge: Sendable {
    /// Node indexes, from zero.
    public let a: Int
    public let b: Int
    /// Measured on the full geometry, so it is longer than ``points`` would say.
    public let lengthKm: Double
    /// From node `a` to node `b`, both ends included, simplified for drawing.
    public let points: [Coordinate]

    /// Distance along ``points`` to each point, scaled so the last is ``lengthKm``.
    let along: [Double]

    public init(a: Int, b: Int, lengthKm: Double, points: [Coordinate]) {
        self.a = a
        self.b = b
        self.lengthKm = lengthKm
        self.points = points
        var along = [0.0]
        along.reserveCapacity(points.count)
        for (start, end) in zip(points, points.dropFirst()) {
            along.append(along[along.count - 1] + GreatCircle.distanceKm(from: start, to: end))
        }
        let drawn = along.last ?? 0
        let scale = drawn > 0 ? lengthKm / drawn : 0
        self.along = along.map { $0 * scale }
    }
}

/// The way a surface leg ran, measured along its network.
public struct TrackPath: Hashable, Sendable {
    /// From the leg's origin to its destination: a straight piece from each end to the
    /// nearest track, and the track between.
    public let coordinates: [Coordinate]
    public let lengthKm: Double
}

/// A network surface legs are measured along: railways, roads or ferry routes
/// (R-PATH-2, R-PATH-5, D-30).
///
/// Each end of a leg is joined to the nearest line within ``snapRadiusKm``, and the leg
/// takes the shortest way along the network between the two. A leg with an end too far
/// from any track, or whose ends the network does not join, has no path and keeps its
/// straight line, marked approximate (R-PATH-3).
public struct TrackNetwork: Sendable {
    public let kind: TrackKind
    /// Which map the network was built from, stored with every leg it measured.
    public let version: String
    public let nodes: [Coordinate]
    public let edges: [TrackEdge]
    private let incident: [[Int]]
    /// Segments by one-degree cell: those of cell `c` are
    /// `segments[cellStart[c] ..< cellStart[c + 1]]`.
    private let cellStart: [Int32]
    private let segments: [SegmentRef]

    /// How far an end may be from the nearest line: a city's centre to its station.
    public static let snapRadiusKm = 25.0
    public static let empty = TrackNetwork(kind: .rail, version: "", nodes: [], edges: [])

    public var isEmpty: Bool {
        edges.isEmpty
    }

    public init(kind: TrackKind, version: String, nodes: [Coordinate], edges: [TrackEdge]) {
        self.kind = kind
        self.version = version
        self.nodes = nodes
        self.edges = edges
        var incident = Array(repeating: [Int](), count: nodes.count)
        for (index, edge) in edges.enumerated() where edge.a < nodes.count && edge.b < nodes.count {
            incident[edge.a].append(index)
            if edge.b != edge.a {
                incident[edge.b].append(index)
            }
        }
        self.incident = incident
        (cellStart, segments) = Self.index(edges)
    }

    /// Two passes, counting then filling, so the index is two flat arrays.
    private static func index(_ edges: [TrackEdge]) -> ([Int32], [SegmentRef]) {
        var counts = [Int32](repeating: 0, count: cellCount + 1)
        func visit(_ body: (Int, SegmentRef) -> Void) {
            for (index, edge) in edges.enumerated() {
                for segment in 0 ..< max(0, edge.points.count - 1) {
                    let ref = SegmentRef(edge: Int32(index), segment: Int32(segment))
                    forEachCell(spanning: edge.points[segment], edge.points[segment + 1]) { cell in
                        body(cell, ref)
                    }
                }
            }
        }
        visit { cell, _ in counts[cell + 1] += 1 }
        for cell in 0 ..< cellCount {
            counts[cell + 1] += counts[cell]
        }
        var next = counts
        var refs = [SegmentRef](
            repeating: SegmentRef(edge: 0, segment: 0),
            count: Int(counts[cellCount])
        )
        visit { cell, ref in
            refs[Int(next[cell])] = ref
            next[cell] += 1
        }
        return (counts, refs)
    }

    // MARK: - Routing

    /// The shortest way along the track between two places, or nil when there is none.
    public func route(from origin: Coordinate, to destination: Coordinate) -> TrackPath? {
        guard let start = snap(origin), let end = snap(destination) else { return nil }
        var best = Double.infinity
        var bestEnd: Int?
        if start.edge == end.edge {
            best = abs(start.along - end.along)
        }
        var search = ShortestPaths(nodes: nodes.count)
        let first = edges[start.edge]
        search.seed(first.a, start.along)
        search.seed(first.b, first.lengthKm - start.along)
        let last = edges[end.edge]
        while let (node, distance) = search.next(), distance < best {
            for (target, rest) in [(last.a, end.along), (last.b, last.lengthKm - end.along)]
                where node == target && distance + rest < best {
                best = distance + rest
                bestEnd = node
            }
            for index in incident[node] {
                let edge = edges[index]
                // Stored a to b, so leaving from its b end runs it backwards.
                let backwards = edge.a != node
                search.relax(
                    from: node,
                    to: backwards ? edge.a : edge.b,
                    via: ShortestPaths.Step(edge: index, reversed: backwards),
                    by: edge.lengthKm
                )
            }
        }
        guard best.isFinite else { return nil }

        var track: [Coordinate]
        if let bestEnd {
            track = points(from: start, toward: search.origin(of: bestEnd))
            track += search.edges(to: bestEnd).flatMap { step in
                step.reversed ? edges[step.edge].points.reversed() : edges[step.edge].points
            }
            track += points(from: end, toward: bestEnd).reversed()
        } else {
            track = points(along: start.edge, from: start, to: end)
        }
        let coordinates = [origin] + track + [destination]
        let length = best + start.offKm + end.offKm
        let straight = GreatCircle.distanceKm(from: origin, to: destination)
        guard length > 0, length <= straight * kind.detourFactor + kind.detourAllowanceKm
        else { return nil }
        return TrackPath(coordinates: coordinates.removingRepeats(), lengthKm: length)
    }

    // MARK: - Snapping

    struct Snap {
        let edge: Int
        let segment: Int
        let point: Coordinate
        /// Along the edge from node `a`, in its own scale.
        let along: Double
        let offKm: Double
    }

    /// The nearest point of track within ``snapRadiusKm``.
    func snap(_ coordinate: Coordinate) -> Snap? {
        var best: Snap?
        let row = Int(floor(coordinate.latitude))
        let column = Int(floor(coordinate.longitude))
        for dRow in -1 ... 1 {
            for dColumn in -1 ... 1 {
                let cell = Self.cell(row + dRow, column + dColumn)
                guard cell >= 0, cell < Self.cellCount else { continue }
                for ref in segments[Int(cellStart[cell]) ..< Int(cellStart[cell + 1])] {
                    let edge = edges[Int(ref.edge)]
                    let segment = Int(ref.segment)
                    let start = edge.points[segment]
                    let end = edge.points[segment + 1]
                    let (point, fraction) = Self.closest(to: coordinate, on: start, end)
                    let off = GreatCircle.distanceKm(from: coordinate, to: point)
                    guard off <= Self.snapRadiusKm, off < best?.offKm ?? .infinity else { continue }
                    let from = edge.along[segment]
                    let to = edge.along[segment + 1]
                    best = Snap(
                        edge: Int(ref.edge),
                        segment: segment,
                        point: point,
                        along: from + (to - from) * fraction,
                        offKm: off
                    )
                }
            }
        }
        return best
    }

    /// The closest point of a short segment, on a local flat projection.
    static func closest(
        to point: Coordinate,
        on start: Coordinate,
        _ end: Coordinate
    ) -> (Coordinate, Double) {
        let scale = cos(point.latitudeRadians)
        let ax = start.longitude * scale, ay = start.latitude
        var bx = end.longitude * scale
        let by = end.latitude
        // A segment across the antimeridian is measured the short way round.
        if bx - ax > 180 * scale {
            bx -= 360 * scale
        }
        if ax - bx > 180 * scale {
            bx += 360 * scale
        }
        let px = point.longitude * scale, py = point.latitude
        let dx = bx - ax, dy = by - ay
        let squared = dx * dx + dy * dy
        let fraction = squared == 0 ? 0 : min(
            1,
            max(0, ((px - ax) * dx + (py - ay) * dy) / squared)
        )
        let longitude = start.longitude + (end.longitude - start.longitude) * fraction
        let latitude = start.latitude + (end.latitude - start.latitude) * fraction
        return (Coordinate(latitude: latitude, longitude: longitude), fraction)
    }

    // MARK: - Geometry

    /// From a snapped point along its edge to one of the edge's ends.
    private func points(from snap: Snap, toward node: Int) -> [Coordinate] {
        let edge = edges[snap.edge]
        if node == edge.a {
            return [snap.point] + edge.points[0 ... snap.segment].reversed()
        }
        return [snap.point] + edge.points[(snap.segment + 1)...]
    }

    /// Between two snapped points on the same edge.
    private func points(along index: Int, from start: Snap, to end: Snap) -> [Coordinate] {
        let points = edges[index].points
        if start.along <= end.along {
            let middle = start.segment < end
                .segment ? Array(points[(start.segment + 1) ... end.segment]) : []
            return [start.point] + middle + [end.point]
        }
        let middle = end.segment < start
            .segment ? Array(points[(end.segment + 1) ... start.segment]) : []
        return [start.point] + middle.reversed() + [end.point]
    }

    struct SegmentRef {
        let edge: Int32
        let segment: Int32
    }

    static let cellCount = 180 * 360

    /// The cell a whole-degree row and column fall in, or -1 off the grid.
    static func cell(_ row: Int, _ column: Int) -> Int {
        guard row >= -90, row < 90 else { return -1 }
        let wrapped = ((column + 180) % 360 + 360) % 360
        return (row + 90) * 360 + wrapped
    }

    /// Every one-degree cell a segment's bounding box touches.
    static func forEachCell(spanning start: Coordinate, _ end: Coordinate, _ body: (Int) -> Void) {
        let south = min(89, Int(floor(min(start.latitude, end.latitude))))
        let north = min(89, Int(floor(max(start.latitude, end.latitude))))
        var west = Int(floor(min(start.longitude, end.longitude)))
        var east = Int(floor(max(start.longitude, end.longitude)))
        if east - west > 180 {
            (west, east) = (east, west + 360)
        }
        for row in south ... north {
            for column in west ... east {
                body(cell(row, column))
            }
        }
    }
}

/// Dijkstra's search from one or two seeded nodes.
private struct ShortestPaths {
    struct Step {
        let edge: Int
        let reversed: Bool
    }

    private var distance: [Double]
    private var previous: [(node: Int, step: Step)?]
    private var heap = MinHeap()

    init(nodes: Int) {
        distance = Array(repeating: .infinity, count: nodes)
        previous = Array(repeating: nil, count: nodes)
    }

    mutating func seed(_ node: Int, _ value: Double) {
        guard value < distance[node] else { return }
        distance[node] = value
        heap.push(value, node)
    }

    mutating func next() -> (Int, Double)? {
        while let (value, node) = heap.pop() {
            if value <= distance[node] {
                return (node, value)
            }
        }
        return nil
    }

    mutating func relax(from node: Int, to other: Int, via step: Step, by length: Double) {
        let value = distance[node] + length
        guard value < distance[other] else { return }
        distance[other] = value
        previous[other] = (node, step)
        heap.push(value, other)
    }

    /// The seeded node a node was reached from.
    func origin(of node: Int) -> Int {
        var current = node
        while let step = previous[current] {
            current = step.node
        }
        return current
    }

    /// The edges from the seed to a node, in riding order.
    func edges(to node: Int) -> [Step] {
        var result: [Step] = []
        var current = node
        while let link = previous[current] {
            result.append(link.step)
            current = link.node
        }
        return result.reversed()
    }
}

/// A binary min-heap of (priority, node).
private struct MinHeap {
    private var items: [(Double, Int)] = []

    mutating func push(_ priority: Double, _ node: Int) {
        items.append((priority, node))
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].0 < items[parent].0 else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var parent = 0
        while true {
            let left = 2 * parent + 1, right = left + 1
            var smallest = parent
            if left < items.count, items[left].0 < items[smallest].0 {
                smallest = left
            }
            if right < items.count, items[right].0 < items[smallest].0 {
                smallest = right
            }
            if smallest == parent {
                break
            }
            items.swapAt(parent, smallest)
            parent = smallest
        }
        return top
    }
}

private extension [Coordinate] {
    func removingRepeats() -> [Coordinate] {
        var result: [Coordinate] = []
        result.reserveCapacity(count)
        for coordinate in self where coordinate != result.last {
            result.append(coordinate)
        }
        return result
    }
}

public extension TrackPath {
    /// The countries the path runs through, in order, from a lookup of the country at a
    /// point (R-PATH-6): Paris to Amsterdam is France, Belgium, the Netherlands.
    ///
    /// The path is sampled every `step` kilometres. Points the lookup cannot place — at
    /// sea, in the Channel Tunnel — are skipped, and a run shorter than `minimum` in the
    /// middle of the path is dropped, so a line along a border that the outlines put a
    /// few hundred metres either side does not cross it again and again.
    func countries(
        sampleEveryKm step: Double = 2,
        ignoringRunsUnderKm minimum: Double = 3,
        lookup: (Coordinate) -> String?
    ) -> [String] {
        var runs: [(code: String, km: Double)] = []
        var travelled = 0.0
        /// The distance between two samples is shared between their runs: the border is
        /// somewhere between them.
        func sample(_ point: Coordinate) {
            guard let code = lookup(point) else { return }
            if runs.last?.code == code {
                runs[runs.count - 1].km += travelled
            } else {
                if !runs.isEmpty {
                    runs[runs.count - 1].km += travelled / 2
                }
                runs.append((code, runs.isEmpty ? 0 : travelled / 2))
            }
            travelled = 0
        }
        sample(coordinates[0])
        for (start, end) in zip(coordinates, coordinates.dropFirst()) {
            let length = GreatCircle.distanceKm(from: start, to: end)
            let pieces = max(1, Int((length / step).rounded(.up)))
            for piece in 1 ... pieces {
                let fraction = Double(piece) / Double(pieces)
                travelled += length / Double(pieces)
                sample(Coordinate(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                ))
            }
        }
        let kept = runs.enumerated().filter { index, run in
            index == 0 || index == runs.count - 1 || run.km >= minimum
        }
        var result: [String] = []
        for (_, run) in kept where run.code != result.last {
            result.append(run.code)
        }
        return result
    }
}
