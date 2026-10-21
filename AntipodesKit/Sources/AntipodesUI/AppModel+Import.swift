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
        let counts = try store.merge(preview.log)
        reload()
        return counts
    }

    /// Reads another app's flight history and matches it to bundled airports (R-LOG-8).
    func readFlightLog(_ data: Data) async throws
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
    func importFlights(_ candidates: [FlightImportCandidate], tripID: UUID?) throws -> Int {
        let legs = candidates.filter(\.include).compactMap(\.leg)
        defer { reload() }
        let trip = try tripID.flatMap { try store.trip(id: $0) }
        try store.logJourneys(legs.map { [$0] }, trip: trip)
        return legs.count
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
