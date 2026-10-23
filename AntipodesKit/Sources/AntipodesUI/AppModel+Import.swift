import AntipodesCore
import AntipodesExport
import AntipodesImport
import AntipodesStore
import Foundation

public extension AppModel {
    /// Restores an Antipodes JSON export, adding only what is not already here.
    func importBackup(_ data: Data) throws -> ImportCounts {
        try importBackup(previewBackup(data))
    }

    /// Reads an Antipodes JSON export and works out what restoring it would add, writing
    /// nothing, so the user can be asked first (R-NAV-2).
    func previewBackup(_ data: Data) throws -> BackupPreview {
        let imported = try TravelLogExport.importLog(fromJSON: data)
        return try BackupPreview(log: imported, additions: store.mergePreview(imported))
    }

    /// Restores a backup the user has already seen the preview of.
    func importBackup(_ preview: BackupPreview) throws -> ImportCounts {
        // Linked photos follow the backup to another device by their iCloud identity.
        let counts = try store.merge(photos.reconcile(preview.log))
        reload()
        return counts
    }

    /// Reads another app's journey history — flights, or a rail log, or any list with a
    /// date and two ends — and matches it to bundled places (R-LOG-8, R-JLOG-7).
    /// Airports are matched by code; stations and towns by name.
    func readJourneyLog(_ data: Data, defaultMode: TravelMode = .flight) async throws
        -> (FlightLogFormat, [FlightImportCandidate]) {
        let dayFirst = Locale.current.region?.identifier != "US"
        let (format, rows) = try FlightLogImport.parse(
            data,
            dayFirst: dayFirst,
            defaultMode: defaultMode
        )
        let candidates = await FlightLogImport.match(
            rows,
            existing: log.allLegs,
            airport: { [weak self] code in await self?.airport(code: code) },
            place: { [weak self] name, _ in await self?.bestPlace(named: name) }
        )
        return (format, candidates)
    }

    /// The bundled place a station or town name most likely means: an exact name first,
    /// then the top result. "Oslo S" or "Bergen stasjon" fall back to fewer words, since
    /// the database has towns rather than stations (D-8).
    func bestPlace(named name: String) async -> PlaceReference? {
        var words = name.split(separator: " ").map(String.init)
        while !words.isEmpty {
            let text = words.joined(separator: " ")
            let results = await search(text, kinds: [.city, .landmark, .airport])
            if let exact = results.first(where: {
                $0.name.compare(text, options: [.caseInsensitive, .diacriticInsensitive])
                    == .orderedSame
            }) ?? results.first {
                return exact.placeReference
            }
            words.removeLast()
        }
        return nil
    }

    /// Logs every included candidate as its own one-leg journey, in one save: an import
    /// lands whole or not at all.
    /// Logs the included rows as journeys of one leg each and, where given, the places
    /// they arrived at as stays (D-32), all in one save.
    func importFlights(
        _ candidates: [FlightImportCandidate],
        tripID: UUID?,
        arrivals: [Arrival] = []
    ) throws -> Int {
        let legs = candidates.filter(\.include).compactMap(\.leg)
        defer { reload() }
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logJourneys(
            legs.map { [$0] },
            trip: trip,
            arrivals: arrivals.map { (place: $0.place, visitType: .stayed, date: $0.date) }
        )
        return legs.count
    }

    /// Logs hikes and rides with their recorded tracks, one journey each, in one save
    /// (R-PATH-1, D-36).
    func importTracks(_ legs: [JourneyLeg]) throws {
        defer { reload() }
        try store.logJourneys(legs.map { [$0] })
    }

    /// Logs the confirmed photo suggestions as visits (R-LOG-7), in one save.
    func importSuggestions(_ suggestions: [VisitSuggestion], tripID: UUID?) throws -> Int {
        defer { reload() }
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logVisits(
            suggestions.map { (place: $0.place, visitType: $0.suggestedType, date: $0.date) },
            trip: trip
        )
        return suggestions.count
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

/// Which import to open.
public enum ImportRequest: String, Identifiable, Sendable {
    /// A flight log, a rail log or any list of journeys (R-LOG-8, R-JLOG-7).
    case journeys
    /// Visits suggested from the photo library (R-LOG-7).
    case photos
    /// Hikes and rides with their tracks, from GPX files or Apple Health (D-36).
    case tracks

    public var id: String {
        rawValue
    }
}
