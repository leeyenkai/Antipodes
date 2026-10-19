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
        ])
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
            ])
        }
        return writer
    }

    static func journeysCSV(_ log: TravelLog) -> CSVWriter {
        var writer = CSVWriter(header: [
            "journey_id", "trip_id", "title", "leg_count", "total_km", "date",
        ])
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
                    leg.origin.id.description,
                    leg.origin.coordinate.map { String($0.latitude) },
                    leg.origin.coordinate.map { String($0.longitude) },
                    leg.destination.name,
                    leg.destination.id.description,
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
                ])
            }
        }
        return writer
    }

    static func wishlistCSV(_ log: TravelLog) -> CSVWriter {
        var writer = CSVWriter(header: [
            "wishlist_id", "place_id", "place_kind", "place_name", "latitude", "longitude",
            "country_code", "route_id", "route_name", "notes", "created_at",
        ])
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
        return try encoder.encode(Document(log: log))
    }

    public static func importLog(fromJSON data: Data) throws -> TravelLog {
        try JSONDecoder().decode(Document.self, from: data).log
    }

    struct Document: Codable {
        /// Bumped whenever the shape changes. Version 2 added leg times, routes, the
        /// wishlist, time zones and short codes; every addition is optional on import, so
        /// a version 1 file still reads.
        var formatVersion = 2
        var application = "Antipodes"
        var exportedAt: String
        var log: TravelLog

        init(log: TravelLog) {
            self.log = log
            exportedAt = ISO8601DateFormatter().string(from: Date())
        }
    }
}
