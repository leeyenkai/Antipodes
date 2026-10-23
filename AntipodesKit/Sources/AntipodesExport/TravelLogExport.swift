import AntipodesCore
import Foundation

/// Exports the user's whole log (R-LOG-9, R-PRIV-6).
///
/// An export has to be complete and readable without the app, because it is the
/// user's escape hatch from a no-account product — if they cannot get their data out,
/// "private by design" is just a cage.
public enum TravelLogExport {
    public enum Format: String, Sendable, CaseIterable, Identifiable {
        case csv
        case json

        public var id: String {
            rawValue
        }

        public var displayName: String {
            switch self {
            case .csv: "CSV"
            case .json: "JSON"
            }
        }

        public var fileExtension: String {
            rawValue
        }
    }

    /// One file per entity for CSV, keyed by filename.
    public static func csvFiles(for log: TravelLog) -> [String: Data] {
        [
            "trips.csv": tripsCSV(log).data(),
            "visits.csv": visitsCSV(log).data(),
            "journeys.csv": journeysCSV(log).data(),
            "legs.csv": legsCSV(log).data(),
            "wishlist.csv": wishlistCSV(log).data(),
        ]
    }

    static func tripsCSV(_ log: TravelLog) -> CSVWriter {
        var writer = CSVWriter(header: ["trip_id", "name", "notes", "created_at"])
        for trip in log.trips.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            writer.append([
                trip.id.uuidString,
                trip.name,
                trip.notes,
                trip.createdAt.map(isoTimestamp),
            ])
        }
        return writer
    }

    static func visitsCSV(_ log: TravelLog) -> CSVWriter {
        var writer = CSVWriter(header: [
            "visit_id", "trip_id", "place_id", "place_kind", "place_name",
            "visit_type", "date", "latitude", "longitude",
            "country_code", "country_name", "continent",
            "region_code", "city_name", "rating", "notes", "time_zone", "code",
            "region_name", "city_id", "created_at",
        ], numericColumns: ["latitude", "longitude", "rating", "city_id"])
        for visit in log.visits.sorted(by: { ($0.date, $0.id.uuidString) < (
            $1.date,
            $1.id.uuidString
        ) }) {
            let place = visit.place
            writer.append([
                visit.id.uuidString,
                visit.tripID?.uuidString,
                place.id.description,
                place.kind.rawValue,
                place.name,
                visit.visitType.rawValue,
                visit.date.exportString,
                place.coordinate.map { String($0.latitude) },
                place.coordinate.map { String($0.longitude) },
                place.countryCode,
                place.countryName,
                place.continent?.rawValue,
                place.qualifiedRegionCode,
                place.cityName,
                visit.rating.map(String.init),
                visit.notes,
                place.timeZoneIdentifier,
                place.code,
                place.regionName,
                place.cityID.map(String.init),
                visit.createdAt.map(isoTimestamp),
            ])
        }
        return writer
    }

    static func journeysCSV(_ log: TravelLog) -> CSVWriter {
        var writer = CSVWriter(header: [
            "journey_id", "trip_id", "title", "leg_count", "total_km", "date",
        ], numericColumns: ["leg_count", "total_km"])
        for journey in log.journeys.sorted(by: { $0.date < $1.date }) {
            writer.append([
                journey.id.uuidString,
                journey.tripID?.uuidString,
                journey.title,
                String(journey.legs.count),
                String(format: "%.3f", journey.totalDistanceKm),
                journey.date.exportString,
            ])
        }
        return writer
    }

    // One column per field, in header order; splitting it would split the header from
    // the values it names.
    // swiftlint:disable:next function_body_length
    static func legsCSV(_ log: TravelLog) -> CSVWriter {
        var writer = CSVWriter(header: [
            "leg_id", "journey_id", "sequence", "mode", "purpose", "date",
            "from_name", "from_code", "from_latitude", "from_longitude",
            "to_name", "to_code", "to_latitude", "to_longitude",
            "distance_km", "distance_source", "operator", "service_number",
            "vehicle", "class", "seat", "rating", "notes",
            "scheduled_departure", "scheduled_arrival", "actual_departure", "actual_arrival",
            "from_time_zone", "to_time_zone", "duration_minutes", "arrival_delay_minutes",
            "missed_connection", "route_id", "route_name", "registration",
            "from_country_code", "to_country_code",
            "from_place_id", "to_place_id", "distance_override_km", "duration_override_minutes",
            "transit_line_id", "network_version",
        ], numericColumns: [
            "sequence", "from_latitude", "from_longitude", "to_latitude", "to_longitude",
            "distance_km", "rating", "duration_minutes", "arrival_delay_minutes", "route_id",
            "distance_override_km", "duration_override_minutes", "transit_line_id",
        ])
        for journey in log.journeys.sorted(by: { $0.date < $1.date }) {
            for (index, leg) in journey.legs.enumerated() {
                let (kilometres, source) = leg.distance
                writer.append([
                    leg.id.uuidString,
                    journey.id.uuidString,
                    String(index + 1),
                    leg.mode.rawValue,
                    leg.purpose.rawValue,
                    leg.date.exportString,
                    leg.origin.name,
                    leg.origin.code,
                    leg.origin.coordinate.map { String($0.latitude) },
                    leg.origin.coordinate.map { String($0.longitude) },
                    leg.destination.name,
                    leg.destination.code,
                    leg.destination.coordinate.map { String($0.latitude) },
                    leg.destination.coordinate.map { String($0.longitude) },
                    String(format: "%.3f", kilometres),
                    source.rawValue,
                    leg.operatorName,
                    leg.serviceNumber,
                    leg.vehicle,
                    leg.travelClass,
                    leg.seat,
                    leg.rating.map(String.init),
                    leg.notes,
                    leg.times.scheduledDeparture?.iso,
                    leg.times.scheduledArrival?.iso,
                    leg.times.actualDeparture?.iso,
                    leg.times.actualArrival?.iso,
                    leg.origin.timeZoneIdentifier,
                    leg.destination.timeZoneIdentifier,
                    leg.durationMinutes.map(String.init),
                    leg.times.arrivalDelayMinutes.map(String.init),
                    leg.missedConnection ? "true" : "false",
                    leg.routeID.map(String.init),
                    leg.routeName,
                    leg.registration,
                    leg.origin.countryCode,
                    leg.destination.countryCode,
                    leg.origin.id.description,
                    leg.destination.id.description,
                    leg.distanceKmOverride.map { String(format: "%.3f", $0) },
                    leg.durationMinutesOverride.map(String.init),
                    leg.transitLineID.map(String.init),
                    leg.networkVersion,
                ])
            }
        }
        return writer
    }

    static func wishlistCSV(_ log: TravelLog) -> CSVWriter {
        var writer = CSVWriter(header: [
            "wishlist_id", "place_id", "place_kind", "place_name", "latitude", "longitude",
            "country_code", "route_id", "route_name", "notes", "created_at",
        ], numericColumns: ["latitude", "longitude", "route_id"])
        for item in log.wishlist.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            writer.append([
                item.id.uuidString,
                item.place?.id.description,
                item.place?.kind.rawValue,
                item.place?.name,
                item.place?.coordinate.map { String($0.latitude) },
                item.place?.coordinate.map { String($0.longitude) },
                item.place?.countryCode,
                item.routeID.map(String.init),
                item.routeName,
                item.notes,
                item.createdAt.map(isoTimestamp),
            ])
        }
        return writer
    }

    static func isoTimestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// The whole log as one JSON document, with a format version so a future importer
    /// can read today's files.
    public static func json(for log: TravelLog) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Readable without the app: "2024-06-12T08:30:00Z", not seconds since 2001.
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Document(log: log))
    }

    /// Why a file could not be restored, in words for the person holding it.
    public enum ImportFailure: Error, Equatable, LocalizedError {
        /// The file is not an Antipodes backup, or is damaged.
        case notABackup
        /// Made by a newer Antipodes, in a format this version cannot read safely.
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .notABackup:
                "This file isn't an Antipodes backup, or it has been damaged."
            case .newerVersion:
                "This backup was made by a newer version of Antipodes. Update the app, "
                    + "then restore it again."
            }
        }
    }

    /// The format version this build writes, and the newest it reads.
    public static let currentFormatVersion = 4

    /// ISO 8601, as version 3 writes; or seconds since 2001, as versions 1 and 2 did.
    static func decodeDate(_ decoder: any Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self),
           let date = ISO8601DateFormatter().date(from: text) {
            return date
        }
        return try Date(timeIntervalSinceReferenceDate: container.decode(Double.self))
    }

    public static func importLog(fromJSON data: Data) throws -> TravelLog {
        struct Header: Decodable {
            let formatVersion: Int?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDate)
        guard let header = try? decoder.decode(Header.self, from: data) else {
            throw ImportFailure.notABackup
        }
        // A newer file may hold things this build would silently drop; refusing is
        // better than restoring half of it.
        if let version = header.formatVersion, version > currentFormatVersion {
            throw ImportFailure.newerVersion(version)
        }
        do {
            return try decoder.decode(Document.self, from: data).log
        } catch {
            throw ImportFailure.notABackup
        }
    }

    struct Document: Codable {
        /// Bumped whenever the shape changes. Version 2 added leg times, routes, the
        /// wishlist, time zones and short codes; every addition is optional on import, so
        /// a version 1 file still reads. Version 3 writes timestamps as ISO 8601 text;
        /// the older numbers still read. Version 4 adds the photos linked to visits and
        /// trips (D-35) — references to the library, never the pictures — and the tracks
        /// recorded on legs; both are optional, so a version 3 file reads as before.
        var formatVersion = TravelLogExport.currentFormatVersion
        var application = "Antipodes"
        var exportedAt: String
        var log: TravelLog

        init(log: TravelLog) {
            self.log = log
            exportedAt = ISO8601DateFormatter().string(from: Date())
        }
    }
}
