import Foundation

/// The eight modes of travel the app logs (§5.1).
public enum TravelMode: String, Sendable, Codable, CaseIterable, Identifiable {
    case flight
    case rail
    case cityTransit
    case coach
    case ferry
    case roadTrip
    case humanPowered
    case cableAndMountain

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .flight: "Flight"
        case .rail: "Rail"
        case .cityTransit: "City transit"
        case .coach: "Coach"
        case .ferry: "Ferry and cruise"
        case .roadTrip: "Road trip"
        case .humanPowered: "Human-powered"
        case .cableAndMountain: "Cable and mountain"
        }
    }

    public var examples: String {
        switch self {
        case .flight: "Scheduled, charter, private"
        case .rail: "Intercity, high-speed, regional, sleeper"
        case .cityTransit: "Metro, tram, light rail, suburban rail, local bus, city ferry"
        case .coach: "Scheduled coaches, airport buses, rural buses"
        case .ferry: "Car ferries, coastal voyages, river and ocean cruises"
        case .roadTrip: "Car, campervan, motorbike"
        case .humanPowered: "Hikes, long-distance trails, cycle tours"
        case .cableAndMountain: "Cable cars, gondolas, funiculars, cog railways"
        }
    }

    public var symbolName: String {
        switch self {
        case .flight: "airplane"
        case .rail: "tram"
        case .cityTransit: "tram.fill.tunnel"
        case .coach: "bus"
        case .ferry: "ferry"
        case .roadTrip: "car"
        case .humanPowered: "figure.walk"
        case .cableAndMountain: "cablecar"
        }
    }

    /// Whether a leg of this mode has an operator, a service number and a timetable.
    public var isScheduledService: Bool {
        switch self {
        case .flight, .rail, .cityTransit, .coach, .ferry, .cableAndMountain: true
        case .roadTrip, .humanPowered: false
        }
    }

    /// A flight's path *is* the great circle, so a straight line is exact rather than
    /// an approximation. Every other mode follows real tracks, roads or sea lanes, and
    /// a straight line there is a labelled fallback (R-PATH-3, R-PATH-4).
    public var greatCircleIsExact: Bool {
        self == .flight
    }

    /// Where a path for this mode comes from (§5.1). Shown in the UI so the user knows
    /// why a distance is marked approximate.
    public var pathSourceDescription: String {
        switch self {
        case .flight: "Great-circle arc between airports"
        case .rail: "Railway lines from OpenStreetMap"
        case .cityTransit: "Line shapes from transit feeds, OpenStreetMap as fallback"
        case .coach: "Roads, snapped with a road router"
        case .ferry: "OpenStreetMap ferry routes; cruises as port-to-port legs"
        case .roadTrip: "Roads, snapped with a road router"
        case .humanPowered: "Trail geometry from OpenStreetMap"
        case .cableAndMountain: "OpenStreetMap aerialway and railway lines"
        }
    }

    /// Modes implemented in the first milestone (§5.8).
    public static var milestoneOne: [TravelMode] {
        [.flight]
    }
}
