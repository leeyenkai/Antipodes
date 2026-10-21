import Foundation

/// The networks surface legs are measured along (D-30): which one a leg uses follows
/// from its mode.
public enum TrackKind: String, CaseIterable, Hashable, Sendable {
    case rail
    /// Roads, with the car ferries that carry them across water.
    case road
    case ferry

    /// A path this many times the straight line, plus ``detourAllowanceKm``, is a gap
    /// in the network rather than a way anyone went, and the straight line, marked
    /// approximate, is nearer the truth. Railways and roads wind round mountains and
    /// fjords — Oslo to Bergen is half as far again as the crow flies — but Natural
    /// Earth leaves out many of the short ferries Norway's coast road takes, and
    /// without them Bergen to Ålesund goes three times round. A ferry sails nearly
    /// straight, so a long way round on the ferry map is other routes joined up.
    public var detourFactor: Double {
        switch self {
        case .rail: 2.5
        case .road: 2.0
        case .ferry: 1.6
        }
    }

    public var detourAllowanceKm: Double {
        self == .ferry ? 10 : 30
    }

    /// What a leg measured on it says it ran along.
    public var routeNoun: String {
        switch self {
        case .rail: "the railway"
        case .road: "the roads"
        case .ferry: "the ferry route"
        }
    }
}

public extension TravelMode {
    /// The network a leg of this mode is measured along, if there is one. A hike or a
    /// cable car keeps its straight line: the roads are not where it went.
    var trackKind: TrackKind? {
        switch self {
        case .rail: .rail
        case .roadTrip, .coach: .road
        case .ferry: .ferry
        case .flight, .cityTransit, .humanPowered, .cableAndMountain: nil
        }
    }
}
