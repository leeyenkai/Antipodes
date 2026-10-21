import Foundation

/// A place in the app a widget can open, as an `antipodes://` URL (decision D-25).
///
/// Built by the widget extension and read by the app, so it lives in Core, which both
/// link. The URL never leaves the device: it is handed from a widget to the app by the
/// system, and nothing in it is ever sent anywhere.
public enum DeepLink: Hashable, Sendable {
    case globe
    case trips
    case stats
    case collections
    case collection(String)
    case trip(UUID)
    case visit(UUID)
    case journey(UUID)
    /// The add sheet, ready to log something.
    case log

    public static let scheme = "antipodes"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .globe: components.host = "globe"
        case .trips: components.host = "trips"
        case .stats: components.host = "stats"
        case .collections: components.host = "collections"
        case .log: components.host = "log"
        case let .collection(id):
            components.host = "collection"
            components.path = "/" + id
        case let .trip(id):
            components.host = "trip"
            components.path = "/" + id.uuidString
        case let .visit(id):
            components.host = "visit"
            components.path = "/" + id.uuidString
        case let .journey(id):
            components.host = "journey"
            components.path = "/" + id.uuidString
        }
        // Every case above is a valid URL by construction.
        return components.url ?? URL(fileURLWithPath: "/")
    }

    /// Reads a link back, or `nil` for anything that is not one of ours.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else {
            return nil
        }
        let arguments = Array(url.pathComponents.dropFirst())
        guard let argument = arguments.first else {
            guard let link = Self.places[host] else { return nil }
            self = link
            return
        }
        guard arguments.count == 1, !argument.isEmpty else { return nil }
        if host == "collection" {
            self = .collection(argument)
            return
        }
        guard let id = UUID(uuidString: argument),
              let record = Self.records[host] else { return nil }
        self = record(id)
    }

    /// The links with nothing after the host.
    private static let places: [String: DeepLink] = [
        "globe": .globe, "trips": .trips, "stats": .stats, "collections": .collections, "log": .log,
    ]

    /// The links that name one record by its identity.
    private static let records: [String: @Sendable (UUID) -> DeepLink] = [
        "trip": { .trip($0) }, "visit": { .visit($0) }, "journey": { .journey($0) },
    ]
}
