import AntipodesCore
import AntipodesExport
import AntipodesGlobe
import AntipodesImport
import AntipodesPlaces
import AntipodesStats
import AntipodesStore
import Foundation
import Observation
import SwiftUI

/// Everything the place database contributes besides search, read once at launch.
public struct Catalogue: Sendable {
    public var collections: [CollectionDefinition] = []
    public var achievements: [AchievementDefinition] = []
    public var routes: [RouteInfo] = []
    public var emissionFactors: EmissionFactorTable = .empty
    public var themes: [ThemeDefinition] = []
    public var countries: [String: CountryFacts] = [:]
}

/// What the add sheet should open on, when something other than the plain sheet is
/// wanted: logging into a particular trip, riding a catalogue route, a dropped pin.
public struct AddRequest: Identifiable, Equatable {
    public enum Start: Equatable {
        case search
        case journey(TravelMode?)
        case route(RouteInfo)
        case pin(Coordinate?)
        case place(PlaceReference)
    }

    public let id = UUID()
    public var start: Start = .search
    public var tripID: UUID?

    public init(start: Start = .search, tripID: UUID? = nil) {
        self.start = start
        self.tripID = tripID
    }
}

/// The app's single piece of shared state.
///
/// Holds the store, the place database, the counting rules and preferences, and caches
/// the computed statistics. Views read it from the environment; there are no per-screen
/// view models (AGENTS.md §4). Statistics are computed off the main actor from value
/// types, so a large log never stalls scrolling.
@MainActor
@Observable
public final class AppModel {
    public let store: TravelLogStore
    public private(set) var places: PlaceDatabase?
    public private(set) var databaseInfo: PlaceDatabaseInfo?
    /// Why the place database could not be opened, shown in the UI instead of an empty
    /// search field that silently never matches.
    public private(set) var placesError: String?

    public private(set) var log: TravelLog = .empty
    public private(set) var statistics: TravelStatistics
    public private(set) var catalogue = Catalogue()
    public private(set) var countryListCounts: [CountryList: Int] = [:]
    /// Facts fetched for the places in the log, so attribute stats can run.
    @ObservationIgnored private var placeFacts: [PlaceID: PlaceFacts] = [:]
    @ObservationIgnored private var computeGeneration = 0
    @ObservationIgnored var borders: CountryBorders?
    #if os(iOS)
        @ObservationIgnored var widgetGlobeSignature: Int?
    #endif
    @ObservationIgnored let bordersURL: URL?
    @ObservationIgnored private let preferences = PreferencesStorage()

    public var rules: CountingRules {
        didSet {
            guard rules != oldValue else { return }
            CountingRulesStorage.save(rules)
            recompute()
        }
    }

    public var appearance: AppearancePreference {
        didSet { preferences.appearance = appearance }
    }

    /// Where the user lives: left out of "days away" and photo suggestions, and the
    /// point the antipode is measured from.
    public var home: PlaceReference? {
        didSet {
            preferences.home = home
            recompute()
        }
    }

    public var hasCompletedOnboarding: Bool {
        didSet { preferences.hasCompletedOnboarding = hasCompletedOnboarding }
    }

    /// Set to open the add sheet from anywhere — a toolbar, a keyboard shortcut, a
    /// tapped empty state.
    public var addRequest: AddRequest?
    /// The last failed operation, for the one app-wide alert.
    public var errorMessage: String?

    public init(store: TravelLogStore, placeDatabaseURL: URL?, bordersURL: URL? = nil) {
        self.store = store
        self.bordersURL = bordersURL
        let loadedRules = CountingRulesStorage.load()
        rules = loadedRules
        appearance = preferences.appearance
        home = preferences.home
        hasCompletedOnboarding = preferences.hasCompletedOnboarding
        statistics = StatisticsEngine.compute(
            for: .empty,
            context: StatisticsContext(rules: loadedRules)
        )

        if let placeDatabaseURL {
            do {
                places = try PlaceDatabase(path: placeDatabaseURL.path(percentEncoded: false))
            } catch {
                placesError = Self.placesUnavailable(because: error)
            }
        } else {
            placesError = Self.placesUnavailable(because: nil)
        }

        reload()
    }

    // MARK: - Loading

    /// Reads everything the database offers besides search. Called once at launch.
    public func start() async {
        guard let places else { return }
        do {
            databaseInfo = try await places.info()
            countryListCounts = try await places.countryListCounts()
            catalogue = try await Catalogue(
                collections: places.collections(),
                achievements: places.achievements(),
                routes: places.routes(),
                emissionFactors: places.emissionFactors(),
                themes: places.themes(),
                countries: places.countryFacts()
            )
        } catch {
            placesError = Self.placesUnavailable(because: error)
        }
        // The denominator for "% of the world" comes from the database rather than a
        // constant, because which places count as a country is the user's choice
        // (Q-4). Applying it here means the number and the list name agree.
        rules.applyCountryCounts(countryListCounts)
        // The facts for the log may already have arrived (reload() fetches them too),
        // in which case refreshFacts() finds nothing new and does not recompute. The
        // catalogue is new either way, so recompute here or collections, badges and
        // carbon would stay empty until the next edit.
        recompute()
        await refreshFacts()
    }

    /// What the user is told when the bundled place database cannot be read. It ships
    /// inside the app, so the only real remedy is reinstalling; the underlying error is
    /// kept for debug builds, where it is the developer reading.
    private static func placesUnavailable(because error: (any Error)?) -> String {
        var message = """
        The built-in list of places could not be opened, so searching and place \
        details are unavailable. Your log is safe. Reinstalling Antipodes should fix this.
        """
        #if DEBUG
            message += "\n\n" + (error.map { String(describing: $0) }
                ?? "places.sqlite is not in the bundle: run scripts/build-placedb.sh and rebuild.")
        #endif
        return message
    }

    /// Re-reads the log and recomputes every statistic.
    ///
    /// Called after any write, so a screen can never show stats that disagree with the
    /// list beside them.
    public func reload() {
        do {
            log = try store.travelLog()
        } catch {
            errorMessage = "Your log could not be read: \(error.localizedDescription)"
            log = .empty
        }
        recompute()
        Task { await refreshFacts() }
    }

    /// Fetches facts for any logged place the cache does not have yet.
    private func refreshFacts() async {
        guard let places else { return }
        let ids = Set(log.visits.map(\.place.id) + log.allLegs.flatMap { [
            $0.origin.id,
            $0.destination.id,
        ] })
        .filter { placeFacts[$0] == nil }
        .filter {
            if case .database = $0 {
                true
            } else {
                false
            }
        }
        guard !ids.isEmpty else { return }
        if let found = try? await places.facts(for: ids) {
            placeFacts.merge(found) { _, new in new }
            recompute()
        }
    }

    public var gazetteer: Gazetteer {
        Gazetteer(places: placeFacts, countries: catalogue.countries, themes: catalogue.themes)
    }

    public var statisticsContext: StatisticsContext {
        StatisticsContext(
            rules: rules,
            gazetteer: gazetteer,
            home: home,
            today: .today(),
            emissionFactors: catalogue.emissionFactors,
            collections: catalogue.collections,
            achievements: catalogue.achievements,
            routes: catalogue.routes
        )
    }

    /// Recomputes off the main actor. A newer request supersedes an older one still
    /// running, so a burst of edits settles on the last.
    private func recompute() {
        computeGeneration += 1
        let generation = computeGeneration
        let log = log
        let context = statisticsContext
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                StatisticsEngine.compute(for: log, context: context)
            }.value
            guard generation == computeGeneration else { return }
            statistics = result
            writeWidgetSnapshot()
        }
    }

    // MARK: - Choices

    /// Switches the country list and repoints the denominator in one step.
    public func selectCountryList(_ list: CountryList) {
        var updated = rules
        updated.countryList = list
        updated.worldCountryCount = countryListCounts[list] ?? list.fallbackCount
        rules = updated
    }

    public func countryCount(for list: CountryList) -> Int {
        countryListCounts[list] ?? list.fallbackCount
    }

    // MARK: - Writing

    /// Runs a write, reloads, and turns a failure into the app-wide alert.
    @discardableResult
    public func perform(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func logVisit(
        place: PlaceReference,
        visitType: VisitType,
        date: FlexibleDate,
        tripID: UUID?,
        rating: Int? = nil,
        notes: String? = nil
    ) throws {
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logVisit(
            place: place,
            visitType: visitType,
            date: date,
            trip: trip,
            rating: rating,
            notes: notes?.trimmedOrNil
        )
        reload()
    }

    public func updateVisit(_ visit: Visit) {
        perform { try store.updateVisit(visit) }
    }

    /// Writes many edited visits in one save, reloading once at the end.
    public func updateVisits(_ visits: [Visit]) {
        perform { try store.updateVisits(visits) }
    }

    public func deleteVisits(_ ids: [UUID]) {
        perform { try store.deleteVisits(ids) }
    }

    public func moveVisits(_ ids: [UUID], toTrip tripID: UUID?) {
        perform { try store.moveVisits(ids, toTrip: tripID) }
    }

    public func logJourney(legs: [JourneyLeg], tripID: UUID?, title: String? = nil) throws {
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logJourney(legs: legs, trip: trip, title: title?.trimmedOrNil)
        reload()
    }

    public func updateJourney(_ journey: Journey) {
        perform { try store.updateJourney(journey) }
    }

    public func deleteJourneys(_ ids: [UUID]) {
        perform { try store.deleteJourneys(ids) }
    }

    public func moveJourneys(_ ids: [UUID], toTrip tripID: UUID?) {
        perform { try store.moveJourneys(ids, toTrip: tripID) }
    }

    /// Duplicates a leg as a new journey dated today (R-JLOG-6).
    public func rideAgain(_ leg: JourneyLeg, tripID: UUID?) {
        perform {
            let trip = try tripID.flatMap { try store.trip(id: $0) }
            try store.logJourney(legs: [leg.rideAgain(on: .day(.today()))], trip: trip)
        }
    }

    @discardableResult
    public func createTrip(name: String?, notes: String? = nil) throws -> Trip {
        let trip = try store.createTrip(name: name?.trimmedOrNil, notes: notes?.trimmedOrNil)
        reload()
        return trip.asTrip
    }

    public func updateTrip(_ trip: Trip) {
        perform { try store.updateTrip(trip) }
    }

    public func deleteTrip(_ id: UUID, deletingContents: Bool) {
        perform { try store.deleteTrip(id: id, deletingContents: deletingContents) }
    }

    // MARK: - Wishlist

    public func isOnWishlist(_ place: PlaceReference) -> Bool {
        log.wishlist.contains { $0.place?.id == place.id }
    }

    public func isOnWishlist(routeID: Int64) -> Bool {
        log.wishlist.contains { $0.routeID == routeID }
    }

    public func addToWishlist(_ place: PlaceReference) {
        guard !isOnWishlist(place) else { return }
        perform { try store.addToWishlist(WishlistItem(place: place, createdAt: Date())) }
    }

    public func addToWishlist(route: RouteInfo) {
        guard !isOnWishlist(routeID: route.id) else { return }
        perform {
            try store.addToWishlist(
                WishlistItem(
                    place: route.start,
                    routeID: route.id,
                    routeName: route.name,
                    createdAt: Date()
                )
            )
        }
    }

    public func removeFromWishlist(_ ids: [UUID]) {
        perform { try store.removeFromWishlist(ids) }
    }

    public func removeFromWishlist(place: PlaceReference) {
        let ids = log.wishlist.filter { $0.place?.id == place.id && $0.routeID == nil }.map(\.id)
        removeFromWishlist(ids)
    }

    /// Wishlist places not yet visited, for the globe's wishlist pins (R-GLOBE-4).
    public var openWishlistPlaces: [PlaceReference] {
        statistics.wishlist.filter { !$0.isVisited }.compactMap(\.item.place)
    }

    // MARK: - Import

    /// Restores an Antipodes JSON export, adding only what is not already here.
    public func importBackup(_ data: Data) throws -> ImportCounts {
        try importBackup(previewBackup(data))
    }

    /// Reads an Antipodes JSON export and works out what restoring it would add, writing
    /// nothing, so the user can be asked first (R-NAV-2).
    public func previewBackup(_ data: Data) throws -> BackupPreview {
        let imported = try TravelLogExport.importLog(fromJSON: data)
        return try BackupPreview(log: imported, additions: store.mergePreview(imported))
    }

    /// Restores a backup the user has already seen the preview of.
    public func importBackup(_ preview: BackupPreview) throws -> ImportCounts {
        let counts = try store.merge(preview.log)
        reload()
        return counts
    }

    /// Reads another app's flight history and matches it to bundled airports (R-LOG-8).
    public func readFlightLog(_ data: Data) async throws
        -> (FlightLogFormat, [FlightImportCandidate]) {
        let dayFirst = Locale.current.region?.identifier != "US"
        let (format, rows) = try FlightLogImport.parse(data, dayFirst: dayFirst)
        let candidates = await FlightLogImport
            .match(rows, existing: log.allLegs) { [weak self] code in
                await self?.airport(code: code)
            }
        return (format, candidates)
    }

    /// Logs every included candidate as its own one-leg journey, in one save: an import
    /// lands whole or not at all.
    public func importFlights(_ candidates: [FlightImportCandidate], tripID: UUID?) throws -> Int {
        let legs = candidates.filter(\.include).compactMap(\.leg)
        defer { reload() }
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logJourneys(legs.map { [$0] }, trip: trip)
        return legs.count
    }

    /// Logs the confirmed photo suggestions as visits (R-LOG-7), in one save.
    public func importSuggestions(_ suggestions: [VisitSuggestion], tripID: UUID?) throws -> Int {
        defer { reload() }
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logVisits(
            suggestions.map { (place: $0.place, visitType: $0.suggestedType, date: $0.date) },
            trip: trip
        )
        return suggestions.count
    }

    /// Erases the log and everything personal kept beside it (R-PRIV-6).
    ///
    /// Home is the user's own location, so it goes too; clearing it also redraws the
    /// widgets' globe without it. Appearance and counting rules are settings, not
    /// data, and stay.
    public func deleteEverything() throws {
        try store.deleteEverything()
        home = nil
        reload()
    }

    // MARK: - Export

    public func exportJSON() throws -> Data {
        try TravelLogExport.json(for: log)
    }

    public func exportCSVFiles() -> [String: Data] {
        TravelLogExport.csvFiles(for: log)
    }
}

/// A backup read but not yet restored: what is in the file, and how much of it is new.
public struct BackupPreview: Sendable {
    public let log: TravelLog
    public let additions: ImportCounts

    /// Trips, places, journeys and wishlist entries in the file.
    public var recordCount: Int {
        log.trips.count + log.visits.count + log.journeys.count + log.wishlist.count
    }

    /// Records in the file that are already in the log, so restoring leaves them alone.
    public var alreadyInLog: Int {
        recordCount - additions.total
    }
}

extension String {
    var trimmedOrNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
