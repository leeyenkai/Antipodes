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
        /// The year it happened, so "how long ago" is right on whichever day it shows.
        public let year: Int
        /// Opens the record in the app (`DeepLink`).
        public let link: URL?

        public init(title: String, subtitle: String, year: Int, link: URL? = nil) {
            self.title = title
            self.subtitle = subtitle
            self.year = year
            self.link = link
        }

        public func yearsAgo(on day: CalendarDate) -> Int {
            day.year - year
        }
    }

    /// The memories for one calendar day.
    public struct MemoryDay: Codable, Hashable, Sendable {
        /// ISO date, `2026-10-21`.
        public let day: String
        public let memories: [Memory]

        public init(day: String, memories: [Memory]) {
            self.day = day
            self.memories = memories
        }
    }

    /// How many days of "on this day" a snapshot carries, so the widget stays right on
    /// the days the app is not opened.
    public static let memoryDayCount = 14

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

    /// Versioned with the shape: a widget reading an older file falls back to its
    /// placeholder until the app writes a new one.
    public static let fileName = "widget-snapshot-2.json"
    public static let globeImageName = "widget-globe.png"

    public let generatedAt: Date
    public let countries: Int
    public let worldPercent: Double
    public let countryListName: String
    public let continents: Int
    public let distanceText: String
    public let placesLogged: Int
    /// "On this day", for the day the snapshot was written and the days after it.
    public let memoryDays: [MemoryDay]
    public let collections: [CollectionSummary]

    public init(
        generatedAt: Date,
        countries: Int,
        worldPercent: Double,
        countryListName: String,
        continents: Int,
        distanceText: String,
        placesLogged: Int,
        memoryDays: [MemoryDay],
        collections: [CollectionSummary]
    ) {
        self.generatedAt = generatedAt
        self.countries = countries
        self.worldPercent = worldPercent
        self.countryListName = countryListName
        self.continents = continents
        self.distanceText = distanceText
        self.placesLogged = placesLogged
        self.memoryDays = memoryDays
        self.collections = collections
    }

    /// What happened on this date in earlier years, as far as the snapshot reaches.
    public func memories(on day: CalendarDate) -> [Memory] {
        memoryDays.first { $0.day == day.iso }?.memories ?? []
    }

    /// Whether two snapshots say the same thing, whenever they were written — so the app
    /// only rewrites the file, and reloads the widgets, when something changed.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        countries == other.countries && worldPercent == other.worldPercent
            && countryListName == other.countryListName && continents == other.continents
            && distanceText == other.distanceText && placesLogged == other.placesLogged
            && memoryDays == other.memoryDays && collections == other.collections
    }

    public static let placeholder = WidgetSnapshot(
        generatedAt: Date(timeIntervalSince1970: 0),
        countries: 24,
        worldPercent: 12.4,
        countryListName: "UN member states",
        continents: 4,
        distanceText: "182,400 km",
        placesLogged: 120,
        memoryDays: [
            MemoryDay(
                day: CalendarDate.today().iso,
                memories: [
                    Memory(title: "Oslo", subtitle: "Stayed", year: CalendarDate.today().year - 3),
                ]
            ),
        ],
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
        guard let container = Self.containerURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(
            to: container.appending(path: Self.fileName),
            options: .atomic
        )
        // The first shape's file, from before memories ran ahead of today.
        try? FileManager.default.removeItem(at: container.appending(path: "widget-snapshot.json"))
    }
}
