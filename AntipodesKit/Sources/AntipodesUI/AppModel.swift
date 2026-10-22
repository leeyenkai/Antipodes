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
    /// The transit systems the log rides, for the city transit stats (R-TRAN-2).
    public private(set) var transitNetwork = TransitNetwork.empty
    public private(set) var databaseInfo: PlaceDatabaseInfo?
    /// Why the place database could not be opened, shown in the UI instead of an empty
    /// search field that silently never matches.
    public private(set) var placesError: String?

    public private(set) var log: TravelLog = .empty
    public private(set) var statistics: TravelStatistics
    /// Bumped each time `statistics` is replaced, so a view that derives something from
    /// the log — a trip's own numbers — knows when to work it out again.
    public private(set) var statisticsRevision = 0
    public private(set) var catalogue = Catalogue()
    public private(set) var countryListCounts: [CountryList: Int] = [:]
    /// Facts fetched for the places in the log, so attribute stats can run.
    @ObservationIgnored private var placeFacts: [PlaceID: PlaceFacts] = [:]
    @ObservationIgnored private var computeGeneration = 0
    /// Bumped on every reload of the log, to invalidate the caches below.
    @ObservationIgnored var logRevision = 0
    /// Each trip's thumbnail scene, built once per change to the log rather than on
    /// every redraw of the list it sits in.
    @ObservationIgnored var tripSceneCache: [UUID: (
        revision: Int,
        rules: CountingRules,
        scene: GlobeScene
    )] = [:]
    @ObservationIgnored var borders: CountryBorders?
    /// The networks surface legs are measured along, each once loaded (D-30).
    @ObservationIgnored var trackNetworks: [TrackKind: TrackNetwork] = [:]
    /// The line each measured surface leg is drawn along, by leg, and the ends it was
    /// found for; and the stops each transit ride passed, in order (R-TRAN-1).
    var measuredPaths: [UUID: [Coordinate]] = [:]
    var transitPaths: [UUID: [Coordinate]] = [:]
    @ObservationIgnored var measuredEnds: [UUID: [Coordinate]] = [:]
    @ObservationIgnored var countriesAlong: [UUID: [String]] = [:]
    #if os(iOS)
        @ObservationIgnored var widgetGlobeSignature: Int?
        @ObservationIgnored var widgetWrite: Task<Void, Never>?
        @ObservationIgnored var lastWidgetSnapshot: WidgetSnapshot?
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

    /// Standard or satellite, for the globe on the home screen and beside the lists.
    public var globeStyle: GlobeStyle {
        didSet { preferences.globeStyle = globeStyle }
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
    /// Why the log could not be read, while it cannot: the app shows that and a retry
    /// in place of every screen.
    public private(set) var logReadError: (any Error)?
    /// A record to open in a tab's list, from a widget's link. The tab's stack takes it
    /// and clears it.
    public var pendingRoute: PendingRoute?
    /// What was just deleted, while the app offers to undo it.
    public var lastDeletion: Deletion?
    /// Counts rides logged again, so the screen can confirm each one with a tap.
    public var rideLoggedAgain = 0
    @ObservationIgnored private var filterGeneration = 0

    /// The slice of the log the Stats screen is showing (§5.7). Not saved: the screen
    /// opens on the whole log.
    public var statsFilter = LogFilter.none {
        didSet {
            guard statsFilter != oldValue else { return }
            recomputeFiltered()
        }
    }

    /// The statistics of that slice, and the slice itself, while a filter is set.
    public private(set) var filteredStatistics: TravelStatistics?
    public private(set) var filteredLog = TravelLog.empty

    public init(store: TravelLogStore, placeDatabaseURL: URL?, bordersURL: URL? = nil) {
        self.store = store
        self.bordersURL = bordersURL
        let loadedRules = CountingRulesStorage.load()
        rules = loadedRules
        appearance = preferences.appearance
        globeStyle = preferences.globeStyle
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
        await preloadBorders()
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
        logRevision += 1
        do {
            log = try store.travelLog()
            logReadError = nil
        } catch {
            // Keep the last log that read cleanly. An empty one would say "Nothing logged
            // yet", invite starting over, and push a blank snapshot to the widgets.
            logReadError = error
            return
        }
        recompute()
        Task { await refreshFacts() }
    }

    /// Fetches facts for any logged place the cache does not have yet, including the
    /// cities a landmark implies, so a capital reached only through its landmarks still
    /// counts as one.
    private func refreshFacts() async {
        guard let places else { return }
        let ids = log.referencedDatabasePlaceIDs.filter { placeFacts[$0] == nil }
        var changed = false
        if !ids.isEmpty, let found = try? await places.facts(for: ids) {
            placeFacts.merge(found) { _, new in new }
            changed = true
        }
        // The networks of every system ridden, loaded once each.
        let lines = Set(log.allLegs.compactMap(\.transitLineID))
        if !lines.isSubset(of: Set(transitNetwork.lines.keys)),
           let systems = try? await places.transitSystems(ofLines: lines),
           let network = try? await places.transitNetwork(systems: systems) {
            transitNetwork = network
            changed = true
        }
        if changed {
            recompute()
        }
        refreshTransitPaths()
        await refreshTracks()
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
            routes: catalogue.routes,
            transit: transitNetwork,
            countriesAlongLegs: countriesAlong
        )
    }

    /// Recomputes off the main actor. A newer request supersedes an older one still
    /// running, so a burst of edits settles on the last.
    func recompute() {
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
            statisticsRevision += 1
            writeWidgetSnapshot()
        }
        recomputeFiltered()
    }

    /// Works out the filtered slice's statistics off the main thread. Until they arrive,
    /// the screen shows the slice's statistics as empty rather than the whole log's.
    private func recomputeFiltered() {
        filterGeneration += 1
        let generation = filterGeneration
        guard statsFilter.isActive else {
            filteredStatistics = nil
            filteredLog = .empty
            return
        }
        let slice = log.restricted(to: statsFilter)
        let context = {
            var context = statisticsContext
            context.rules = statsFilter.rules(from: rules)
            return context
        }()
        filteredLog = slice
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                StatisticsEngine.compute(for: slice, context: context)
            }.value
            guard generation == filterGeneration else { return }
            filteredStatistics = result
        }
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

    @discardableResult
    public func updateVisit(_ visit: Visit) -> Bool {
        perform { try store.updateVisit(visit) }
    }

    /// Writes many edited visits in one save, reloading once at the end.
    public func updateVisits(_ visits: [Visit]) {
        perform { try store.updateVisits(visits) }
    }

    public func deleteVisits(_ ids: [UUID]) {
        let removed = log.visits.filter { ids.contains($0.id) }
        if perform({ try store.deleteVisits(ids) }) {
            offerUndo(Deletion(
                message: removed.count == 1
                    ? "Deleted \(removed[0].place.name)" : "Deleted \(removed.count) places",
                records: TravelLog(visits: removed)
            ))
        }
    }

    public func moveVisits(_ ids: [UUID], toTrip tripID: UUID?) {
        perform { try store.moveVisits(ids, toTrip: tripID) }
    }

    public func logJourney(legs: [JourneyLeg], tripID: UUID?, title: String? = nil) throws {
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logJourney(legs: legs, trip: trip, title: title?.trimmedOrNil)
        reload()
    }

    @discardableResult
    public func updateJourney(_ journey: Journey) -> Bool {
        perform { try store.updateJourney(journey) }
    }

    public func deleteJourneys(_ ids: [UUID]) {
        let removed = log.journeys.filter { ids.contains($0.id) }
        if perform({ try store.deleteJourneys(ids) }) {
            offerUndo(Deletion(
                message: removed.count == 1
                    ? "Deleted \(removed[0].displayTitle)" : "Deleted \(removed.count) journeys",
                records: TravelLog(journeys: removed)
            ))
        }
    }

    public func moveJourneys(_ ids: [UUID], toTrip tripID: UUID?) {
        perform { try store.moveJourneys(ids, toTrip: tripID) }
    }

    /// Duplicates a leg as a new journey dated today (R-JLOG-6).
    /// Logs the same ride again, dated today (R-JLOG-6). It joins the original's trip only
    /// while that trip is still under way — its last record no more than a week ago — so
    /// a holiday's second tram files with the holiday and a later commute does not.
    public func rideAgain(_ leg: JourneyLeg, tripID: UUID?) {
        let today = CalendarDate.today()
        let ongoingTrip = tripID.flatMap { id in
            dates(ofTrip: id).flatMap { $0.end.days(to: today) <= 7 ? id : nil }
        }
        if perform({
            let trip = try ongoingTrip.flatMap { try store.trip(id: $0) }
            try store.logJourney(legs: [leg.rideAgain(on: .day(today))], trip: trip)
        }) {
            rideLoggedAgain += 1
        }
    }

    /// The alert for a trip that could not be made.
    static func tripNotCreated(_ error: any Error) -> String {
        "The trip couldn't be created. \(error.localizedDescription)"
    }

    @discardableResult
    public func createTrip(name: String?, notes: String? = nil) throws -> Trip {
        let trip = try store.createTrip(name: name?.trimmedOrNil, notes: notes?.trimmedOrNil)
        reload()
        return trip.asTrip
    }

    @discardableResult
    public func updateTrip(_ trip: Trip) -> Bool {
        perform { try store.updateTrip(trip) }
    }

    public func deleteTrip(_ id: UUID, deletingContents: Bool) {
        guard let trip = log.trip(id: id) else { return }
        let contents = log.restricted(toTrip: id)
        let name = trip.name ?? "trip"
        if perform({ try store.deleteTrip(id: id, deletingContents: deletingContents) }) {
            offerUndo(Deletion(
                message: "Deleted \(name)",
                records: deletingContents ? contents : TravelLog(trips: [trip]),
                refile: deletingContents ? nil : (
                    trip: id,
                    visits: contents.visits.map(\.id),
                    journeys: contents.journeys.map(\.id)
                )
            ))
        }
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
}
