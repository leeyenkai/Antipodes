import Foundation

/// The networks surface legs are measured along (D-30): which one a leg uses follows
/// from its mode, and for a hike or a ride from its activity (D-36).
public enum TrackKind: String, CaseIterable, Hashable, Sendable {
    case rail
    /// Roads, with the car ferries that carry them across water.
    case road
    case ferry
    /// Signed hiking routes, from the OpenStreetMap pack, region by region (D-36).
    case hiking
    /// Signed cycle routes, the same way.
    case cycling
    /// The world's passenger aerial lifts, station to station, from the same pack: a
    /// gondola and the cable car above it make one ride up.
    case lift

    /// The networks in the place database, whole-world and one each. Trails come from
    /// the route pack, one network a region.
    public static let bundled: [TrackKind] = [.rail, .road, .ferry]

    public var isTrail: Bool {
        self == .hiking || self == .cycling
    }

    /// Read from the OpenStreetMap route pack rather than the place database (D-36).
    public var isFromRoutePack: Bool {
        !Self.bundled.contains(self)
    }

    /// How far a leg's end may be from the network: a city's centre to its station for a
    /// train, but only a short walk to the trailhead for a hike — a town on the far side
    /// of a valley is not where the trail starts.
    public var snapRadiusKm: Double {
        switch self {
        case .hiking, .cycling: 3
        // A lift is boarded at its station; from a town's centre that is a short walk.
        case .lift: 1.5
        case .rail, .road, .ferry: 25
        }
    }

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
        // Paths zigzag up mountains; a marked trail three times the straight line is
        // still a hike, but more is the network joining two valleys the long way.
        case .hiking: 3.0
        case .cycling: 2.2
        case .lift: 2.0
        }
    }

    public var detourAllowanceKm: Double {
        switch self {
        case .ferry: 10
        case .hiking, .cycling: 5
        case .lift: 2
        case .rail, .road: 30
        }
    }

    /// What a leg measured on it says it ran along.
    public var routeNoun: String {
        switch self {
        case .rail: "the railway"
        case .road: "the roads"
        case .ferry: "the ferry route"
        case .hiking: "the marked trails"
        case .cycling: "the cycle routes"
        case .lift: "the lifts"
        }
    }
}

public extension TravelMode {
    /// The network a leg of this mode is measured along, if there is one. A hike's or
    /// a ride's depends on which it was (`JourneyLeg.trackKind`); the roads are not
    /// where it went.
    var trackKind: TrackKind? {
        switch self {
        case .rail: .rail
        case .roadTrip, .coach: .road
        case .ferry: .ferry
        case .cableAndMountain: .lift
        case .flight, .cityTransit, .humanPowered: nil
        }
    }
}

public extension TrackNetwork {
    /// How far a catalogue route's own length and the network's way may differ before
    /// the network's way is taken to be a different route.
    static let catalogueTolerance = 0.15

    /// The way a leg ran on this network, or nil.
    ///
    /// A leg that already has a length of another kind — a catalogue route's — keeps it,
    /// and is drawn along the network only where the network's way agrees with it to
    /// within ``catalogueTolerance``: the shortest way from Moscow to Vladivostok cuts
    /// through Kazakhstan, which the Trans-Siberian does not.
    func route(for leg: JourneyLeg) -> TrackPath? {
        guard let origin = leg.origin.coordinate, let destination = leg.destination.coordinate,
              let path = route(from: origin, to: destination)
        else { return nil }
        if let known = leg.storedPathLengthKm, !leg.isMeasuredAlongTrack,
           abs(path.lengthKm - known) > known * Self.catalogueTolerance {
            return nil
        }
        return path
    }
}
