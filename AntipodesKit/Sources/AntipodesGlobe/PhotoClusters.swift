import AntipodesCore
import Foundation

/// A photo with a place, for the globe's photo layer (R-PHOTO-4).
public struct PhotoPoint: Sendable, Hashable {
    public let id: String
    public let coordinate: Coordinate
    public let takenAt: Date?

    public init(id: String, coordinate: Coordinate, takenAt: Date?) {
        self.id = id
        self.coordinate = coordinate
        self.takenAt = takenAt
    }
}

/// Photos taken close together, drawn as one bubble with a count.
public struct PhotoCluster: Identifiable, Sendable, Hashable {
    /// Stable for the same cell at the same zoom band, so a selection survives a redraw.
    public let id: UUID
    /// The middle of the photos in it, not the corner of its cell.
    public let coordinate: Coordinate
    /// Newest first.
    public let photoIDs: [String]
    public let first: Date?
    public let last: Date?

    public var count: Int {
        photoIDs.count
    }
}

/// Every photo with a location, grouped at each zoom band (R-PHOTO-4).
///
/// A library can hold a hundred thousand photos, far too many to draw one by one or to
/// group while the globe turns. They are grouped once, on a grid of equal degrees for
/// each band — eight degrees across the whole Earth, halving each time the zoom doubles
/// — and the globe draws the band for its zoom. Grouping is pure and runs off the main
/// thread when the library changes.
public struct PhotoClusters: Sendable {
    /// The cell size of each band, in degrees.
    public static let bandDegrees: [Double] = [8, 4, 2, 1, 0.5, 0.25]

    public let levels: [[PhotoCluster]]

    public static let empty = PhotoClusters(levels: Array(repeating: [], count: bandDegrees.count))

    public var isEmpty: Bool {
        levels.allSatisfy(\.isEmpty)
    }

    public var photoCount: Int {
        levels.first?.reduce(0) { $0 + $1.count } ?? 0
    }

    init(levels: [[PhotoCluster]]) {
        self.levels = levels
    }

    /// Groups photos given newest first, as the library hands them over.
    public init(_ photos: [PhotoPoint]) {
        levels = Self.bandDegrees.enumerated().map { band, degrees in
            Self.group(photos, band: band, degrees: degrees)
        }
    }

    /// The band to draw at a camera zoom: one band finer each time the zoom doubles.
    public static func band(forZoom zoom: Double) -> Int {
        let band = Int(log2(max(1, zoom)).rounded(.down))
        return min(max(0, band), bandDegrees.count - 1)
    }

    public func clusters(forZoom zoom: Double) -> [PhotoCluster] {
        levels[Self.band(forZoom: zoom)]
    }

    private struct Cell: Hashable {
        let latitude: Int
        let longitude: Int
    }

    private struct Accumulator {
        var x = 0.0, y = 0.0, z = 0.0
        var anchor: Coordinate?
        /// Each photo with its place in the input, which is newest first.
        var members: [(order: Int, id: String)] = []
        var first: Date?
        var last: Date?

        mutating func absorb(_ other: Accumulator) {
            x += other.x
            y += other.y
            z += other.z
            members += other.members
            first = [first, other.first].compactMap(\.self).min()
            last = [last, other.last].compactMap(\.self).max()
        }
    }

    private static func group(
        _ photos: [PhotoPoint],
        band: Int,
        degrees: Double
    ) -> [PhotoCluster] {
        var cells: [Cell: Accumulator] = [:]
        for (order, photo) in photos.enumerated() {
            let cell = Cell(
                latitude: Int((photo.coordinate.latitude / degrees).rounded(.down)),
                longitude: Int((photo.coordinate.longitude / degrees).rounded(.down))
            )
            let vector = photo.coordinate.unitVector
            var sum = cells[cell, default: Accumulator()]
            sum.x += vector.x
            sum.y += vector.y
            sum.z += vector.z
            sum.anchor = sum.anchor ?? photo.coordinate
            sum.members.append((order, photo.id))
            if let taken = photo.takenAt {
                sum.first = min(sum.first ?? taken, taken)
                sum.last = max(sum.last ?? taken, taken)
            }
            cells[cell] = sum
        }
        // A grid cuts through places: photos either side of a cell's edge would be two
        // bubbles on top of each other. A cell whose middle is close to a busier
        // neighbour's joins it.
        let joinKm = degrees * 111 * 0.5
        var kept: [(cell: Cell, sum: Accumulator)] = []
        var keptAt: [Cell: Int] = [:]
        let busiestFirst = cells.sorted { a, b in
            (a.value.members.count, b.key.latitude, b.key.longitude)
                > (b.value.members.count, a.key.latitude, a.key.longitude)
        }
        for (cell, sum) in busiestFirst {
            let here = mean(sum) ?? sum.anchor
            var home: Int?
            neighbours: for dLat in -1 ... 1 {
                for dLon in -1 ... 1 {
                    guard let index = keptAt[Cell(
                        latitude: cell.latitude + dLat,
                        longitude: cell.longitude + dLon
                    )],
                        let here, let there = mean(kept[index].sum) ?? kept[index].sum.anchor,
                        GreatCircle.distanceKm(from: here, to: there) < joinKm else { continue }
                    home = index
                    break neighbours
                }
            }
            if let home {
                kept[home].sum.absorb(sum)
                keptAt[cell] = home
            } else {
                keptAt[cell] = kept.count
                kept.append((cell, sum))
            }
        }
        return kept.map { cell, sum in
            PhotoCluster(
                id: stableID(band: band, cell: cell),
                coordinate: mean(sum) ?? sum.anchor ?? Coordinate(latitude: 0, longitude: 0),
                photoIDs: sum.members.sorted { $0.order < $1.order }.map(\.id),
                first: sum.first,
                last: sum.last
            )
        }
        // Largest last, so the busiest places are drawn on top.
        .sorted { ($0.count, $0.id.uuidString) < ($1.count, $1.id.uuidString) }
    }

    /// The direction the photos' unit vectors average to, as a coordinate.
    private static func mean(_ sum: Accumulator) -> Coordinate? {
        let length = (sum.x * sum.x + sum.y * sum.y + sum.z * sum.z).squareRoot()
        guard length > 1e-9 else { return nil }
        let latitude = asin(max(-1, min(1, sum.z / length))) * 180 / .pi
        let longitude = atan2(sum.y / length, sum.x / length) * 180 / .pi
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    private static func stableID(band: Int, cell: Cell) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = 0x50 // "P", for photo
        bytes[1] = UInt8(band)
        withUnsafeBytes(of: Int32(cell.latitude).bigEndian) { bytes.replaceSubrange(
            4 ..< 8,
            with: $0
        ) }
        withUnsafeBytes(of: Int32(cell.longitude).bigEndian) { bytes.replaceSubrange(
            8 ..< 12,
            with: $0
        ) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public extension [PhotoCluster] {
    /// The cluster nearest a point in the view, within `tolerance` points, on the
    /// visible side of the globe.
    func cluster(
        at point: GlobePoint,
        globe: OrthographicGlobe,
        tolerance: Double = 22
    ) -> PhotoCluster? {
        var best: (cluster: PhotoCluster, distance: Double)?
        for cluster in self {
            let projected = globe.project(cluster.coordinate)
            guard projected.isVisible else { continue }
            let distance = projected.point.distance(to: point)
            guard distance <= tolerance + PhotoClusters.bubbleRadius(cluster.count)
            else { continue }
            if best == nil || distance < best!.distance {
                best = (cluster, distance)
            }
        }
        return best?.cluster
    }
}

public extension PhotoClusters {
    /// How big a bubble is drawn for a number of photos, in points: larger for more,
    /// but slowly, so a city of thousands does not cover its country.
    static func bubbleRadius(_ count: Int) -> Double {
        9 + 3 * log10(Double(max(1, count)))
    }
}
