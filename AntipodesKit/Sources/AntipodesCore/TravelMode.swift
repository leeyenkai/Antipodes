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

    /// How the app draws and measures a leg of this mode today (§5.1). Shown beside a
    /// leg so the user knows why its distance is, or is not, marked approximate.
    ///
    /// Real track, road and sea geometry needs a route pack built from OpenStreetMap,
    /// which ships separately if at all (decision D-8), so every surface mode is a
    /// labelled straight line until then (R-PATH-3).
    public var pathSourceDescription: String {
        switch self {
        case .flight:
            "Great-circle arc between the airports — the path the distance is measured on."
        case .rail, .cityTransit, .coach, .ferry, .roadTrip, .humanPowered, .cableAndMountain:
            "A straight line between the two ends. The real route is longer, so the "
                + "distance is marked approximate unless you enter it or ride a catalogue "
                + "route."
        }
    }

    /// What the vehicle field means for this mode, for its placeholder text.
    public var vehicleLabel: String {
        switch self {
        case .flight: "Aircraft type"
        case .rail: "Train type"
        case .cityTransit: "Vehicle"
        case .coach: "Bus model"
        case .ferry: "Ship"
        case .roadTrip: "Car, campervan or motorbike"
        case .humanPowered: "Bike or on foot"
        case .cableAndMountain: "Cabin or car"
        }
    }

    /// What the service-number field means, where the mode has one.
    public var serviceNumberLabel: String? {
        switch self {
        case .flight: "Flight number"
        case .rail: "Train number"
        case .cityTransit: "Line"
        case .coach: "Route number"
        case .ferry: "Sailing"
        case .roadTrip, .humanPowered, .cableAndMountain: nil
        }
    }

    /// The classes worth offering in a picker. Free text is still accepted.
    public var classOptions: [String] {
        switch self {
        case .flight: ["Economy", "Premium economy", "Business", "First"]
        case .rail: ["Standard", "First", "Sleeper", "Couchette"]
        case .coach: ["Standard", "Premium"]
        case .ferry: ["Foot passenger", "Car passenger", "Cabin", "Deck"]
        case .cityTransit, .roadTrip, .humanPowered, .cableAndMountain: []
        }
    }

    /// What the origin and destination usually are, for the search prompt.
    public var endpointNoun: String {
        switch self {
        case .flight: "airport"
        case .rail: "station or city"
        case .cityTransit: "stop or city"
        case .coach: "stop or city"
        case .ferry: "port or city"
        case .roadTrip: "town"
        case .humanPowered: "start or end point"
        case .cableAndMountain: "station"
        }
    }

    /// Which place kinds the search offers for this mode's ends. Flights only ever go
    /// between airports; everything else can start or end anywhere.
    public var endpointKinds: Set<PlaceKind>? {
        self == .flight ? [.airport] : [.city, .landmark, .airport, .region]
    }

    /// Modes implemented in the first milestone (§5.8).
    public static var milestoneOne: [TravelMode] {
        [.flight]
    }

    /// Every mode the v1 app logs (R-LOG-6).
    public static var loggable: [TravelMode] {
        allCases
    }
}
