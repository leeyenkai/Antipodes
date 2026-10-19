import Foundation

/// What the Home and Lock Screen widgets show (R-SHARE-2), written by the app into the
/// shared app-group container whenever the log changes.
///
/// A widget cannot open the SwiftData store or the place database cheaply, so the app
/// hands it the few numbers it draws. Everything here is derived from the user's own
/// log on the device; the file never leaves it.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Memory: Codable, Hashable, Sendable {
        public let title: String
        public let subtitle: String
        public let yearsAgo: Int

        public init(title: String, subtitle: String, yearsAgo: Int) {
            self.title = title
            self.subtitle = subtitle
            self.yearsAgo = yearsAgo
        }
    }

    public struct CollectionSummary: Codable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let symbol: String?
        public let visited: Int
        public let total: Int

        public init(id: String, name: String, symbol: String?, visited: Int, total: Int) {
            self.id = id
            self.name = name
            self.symbol = symbol
            self.visited = visited
            self.total = total
        }
    }

    public static let fileName = "widget-snapshot.json"
    public static let globeImageName = "widget-globe.png"

    public let generatedAt: Date
    public let countries: Int
    public let worldPercent: Double
    public let countryListName: String
    public let continents: Int
    public let distanceText: String
    public let placesLogged: Int
    /// "On this day" entries for the day the snapshot was written.
    public let memoriesDay: String
    public let memories: [Memory]
    public let collections: [CollectionSummary]

    public init(
        generatedAt: Date,
        countries: Int,
        worldPercent: Double,
        countryListName: String,
        continents: Int,
        distanceText: String,
        placesLogged: Int,
        memoriesDay: String,
        memories: [Memory],
        collections: [CollectionSummary]
    ) {
        self.generatedAt = generatedAt
        self.countries = countries
        self.worldPercent = worldPercent
        self.countryListName = countryListName
        self.continents = continents
        self.distanceText = distanceText
        self.placesLogged = placesLogged
        self.memoriesDay = memoriesDay
        self.memories = memories
        self.collections = collections
    }

    public static let placeholder = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        countries: 24,
        worldPercent: 12.4,
        countryListName: "UN member states",
        continents: 4,
        distanceText: "182,400 km",
        placesLogged: 120,
        memoriesDay: "",
        memories: [Memory(title: "Oslo", subtitle: "Stayed", yearsAgo: 3)],
        collections: [
            CollectionSummary(
                id: "nordic-capitals", name: "Nordic capitals", symbol: "snowflake", visited: 3,
                total: 5
            ),
        ]
    )

    /// The app group both the app and the widget extension are entitled to.
    public static let appGroup = "group.com.leeyenkai.antipodes"

    /// Where the snapshot lives, or `nil` when the app group is not available — a build
    /// without the entitlement, where the widget then shows its placeholder.
    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    public static func load() -> WidgetSnapshot? {
        guard let url = containerURL()?.appending(path: fileName),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save() throws {
        guard let url = Self.containerURL()?.appending(path: Self.fileName) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
