import Foundation

/// A Köppen-Geiger climate zone, by its code ("Cfb"), with the names people use.
public struct ClimateZone: Hashable, Sendable, Comparable, Identifiable {
    /// The five main climates, the zone code's first letter.
    public enum Group: String, Sendable, CaseIterable, Comparable {
        case tropical = "A"
        case arid = "B"
        case temperate = "C"
        case continental = "D"
        case polar = "E"

        public var name: String {
            switch self {
            case .tropical: "Tropical"
            case .arid: "Arid"
            case .temperate: "Temperate"
            case .continental: "Continental"
            case .polar: "Polar"
            }
        }

        public static func < (lhs: Group, rhs: Group) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let code: String
    public let group: Group

    public var id: String {
        code
    }

    public init?(code: String) {
        guard let first = code.first, let group = Group(rawValue: String(first)),
              Self.names[code] != nil
        else { return nil }
        self.code = code
        self.group = group
    }

    /// "Temperate oceanic".
    public var name: String {
        Self.names[code] ?? code
    }

    public static func < (lhs: ClimateZone, rhs: ClimateZone) -> Bool {
        lhs.code < rhs.code
    }

    /// The conventional English names of the thirty classes.
    private static let names: [String: String] = [
        "Af": "Tropical rainforest",
        "Am": "Tropical monsoon",
        "Aw": "Tropical savanna",
        "BWh": "Hot desert",
        "BWk": "Cold desert",
        "BSh": "Hot semi-arid",
        "BSk": "Cold semi-arid",
        "Csa": "Hot-summer Mediterranean",
        "Csb": "Warm-summer Mediterranean",
        "Csc": "Cold-summer Mediterranean",
        "Cwa": "Monsoon-influenced humid subtropical",
        "Cwb": "Subtropical highland",
        "Cwc": "Cold subtropical highland",
        "Cfa": "Humid subtropical",
        "Cfb": "Temperate oceanic",
        "Cfc": "Subpolar oceanic",
        "Dsa": "Mediterranean-influenced hot-summer continental",
        "Dsb": "Mediterranean-influenced warm-summer continental",
        "Dsc": "Mediterranean-influenced subarctic",
        "Dsd": "Mediterranean-influenced extremely cold subarctic",
        "Dwa": "Monsoon-influenced hot-summer continental",
        "Dwb": "Monsoon-influenced warm-summer continental",
        "Dwc": "Monsoon-influenced subarctic",
        "Dwd": "Monsoon-influenced extremely cold subarctic",
        "Dfa": "Hot-summer humid continental",
        "Dfb": "Warm-summer humid continental",
        "Dfc": "Subarctic",
        "Dfd": "Extremely cold subarctic",
        "ET": "Tundra",
        "EF": "Ice cap",
    ]
}
