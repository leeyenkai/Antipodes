import AntipodesCore
import AntipodesExport
import AntipodesPlaces
import AntipodesStats
import AntipodesStore
import Foundation
import Observation

/// The app's single piece of shared state.
///
/// Holds the store, the place database and the counting rules, and caches the computed
/// statistics. Views read it from the environment; there are no per-screen view models
/// (AGENTS.md §4).
@MainActor
@Observable
public final class AppModel {
    public private(set) var store: TravelLogStore
    public private(set) var places: PlaceDatabase?
    public private(set) var databaseInfo: PlaceDatabaseInfo?

    /// Why the place database could not be opened, shown in the UI instead of an empty
    /// search field that silently never matches.
    public private(set) var placesError: String?

    public private(set) var log: TravelLog = .empty
    public private(set) var statistics: TravelStatistics

    public var rules: CountingRules {
        didSet {
            guard rules != oldValue else { return }
            CountingRulesStorage.save(rules)
            recomputeStatistics()
        }
    }

    public init(store: TravelLogStore, placeDatabaseURL: URL?) {
        self.store = store
        let loadedRules = CountingRulesStorage.load()
        rules = loadedRules
        statistics = StatisticsEngine.compute(for: .empty, rules: loadedRules)

        if let placeDatabaseURL {
            do {
                places = try PlaceDatabase(path: placeDatabaseURL.path(percentEncoded: false))
            } catch {
                placesError = String(describing: error)
            }
        } else {
            placesError = """
            The bundled place database is missing. Run scripts/build-placedb.sh and \
            rebuild the app.
            """
        }

        reload()
    }

    /// Re-reads the log and recomputes every statistic.
    ///
    /// Called after any write. At M1 scale this is a few milliseconds, and doing it in
    /// one place means a screen can never show stats that disagree with the list
    /// beside them.
    public func reload() {
        do {
            log = try store.travelLog()
        } catch {
            log = .empty
        }
        recomputeStatistics()
    }

    private func recomputeStatistics() {
        statistics = StatisticsEngine.compute(for: log, rules: rules)
    }

    public func loadDatabaseInfo() async {
        guard let places else { return }
        databaseInfo = try? await places.info()
        countryListCounts = await (try? places.countryListCounts()) ?? [:]
        // The denominator for "% of the world" comes from the database rather than a
        // constant, because which places count as a country is the user's choice
        // (Q-4). Applying it here means the number and the list name on screen agree.
        rules.applyCountryCounts(countryListCounts)
    }

    /// How many countries each selectable list holds, read from the place database.
    public private(set) var countryListCounts: [CountryList: Int] = [:]

    /// Switches the country list and repoints the denominator in one step.
    public func selectCountryList(_ list: CountryList) {
        var updated = rules
        updated.countryList = list
        updated.worldCountryCount = countryListCounts[list] ?? list.fallbackCount
        rules = updated
    }

    // MARK: - Search

    public func search(_ text: String, kinds: Set<PlaceKind>?) async -> [PlaceSearchResult] {
        guard let places, text.trimmingCharacters(in: .whitespaces).count >= 1 else { return [] }
        return await (try? places.search(text, kinds: kinds)) ?? []
    }

    /// Resolves a dropped pin's country so a custom place still counts in coverage
    /// (R-LOG-5).
    public func resolveCountry(for coordinate: Coordinate) async -> PlaceSearchResult? {
        guard let places else { return nil }
        return try? await places.approximateCountry(for: coordinate)
    }

    // MARK: - Writing

    public func logVisit(
        place: PlaceReference,
        visitType: VisitType,
        date: FlexibleDate,
        tripID: UUID?
    ) throws {
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logVisit(place: place, visitType: visitType, date: date, trip: trip)
        reload()
    }

    public func logFlight(
        from origin: PlaceReference,
        to destination: PlaceReference,
        date: FlexibleDate,
        airline: String?,
        flightNumber: String?,
        tripID: UUID?
    ) throws {
        let leg = JourneyLeg(
            mode: .flight,
            origin: origin,
            destination: destination,
            date: date,
            operatorName: airline?.isEmpty == true ? nil : airline,
            serviceNumber: flightNumber?.isEmpty == true ? nil : flightNumber
        )
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logJourney(legs: [leg], trip: trip)
        reload()
    }

    @discardableResult
    public func createTrip(name: String?) throws -> Trip {
        let trip = try store.createTrip(name: name)
        reload()
        return trip.asTrip
    }

    public func deleteEverything() throws {
        try store.deleteEverything()
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
