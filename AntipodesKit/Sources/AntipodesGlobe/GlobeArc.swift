import AntipodesCore
import Foundation

/// A leg as the globe draws it.
public struct GlobeArc: Identifiable, Sendable {
    public let id: UUID
    public let mode: TravelMode
    public let origin: PlaceReference
    public let destination: PlaceReference
    /// The sampled great circle, straight from `AntipodesCore`, or the track a rail leg
    /// was measured along. The globe never works out a path of its own, so the line
    /// drawn is the line the distance was measured along (R-PATH-4, AGENTS.md §7).
    public let path: [Coordinate]
    public let date: FlexibleDate
    /// A great circle standing in for a road, track or sea lane: drawn dashed, as its
    /// distance is marked approximate (R-PATH-3).
    public let isApproximate: Bool

    public var title: String {
        "\(origin.name) → \(destination.name)"
    }
}

/// A catalogue route on the wishlist, drawn as a dashed line between its two ends
/// (R-WISH-1). Not a journey: it adds nothing to any count or distance.
public struct GlobeWishlistRoute: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let path: [Coordinate]

    public init(id: UUID, name: String, from start: Coordinate, to end: Coordinate) {
        self.id = id
        self.name = name
        path = GreatCircle.arc(from: start, to: end, segments: 32)
    }
}
