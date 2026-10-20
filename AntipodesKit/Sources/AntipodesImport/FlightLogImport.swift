import AntipodesCore
import Foundation

/// One flight read from another app's export, before it is matched to airports.
public struct FlightImportRow: Hashable, Sendable, Identifiable {
    public var id: Int {
        line
    }

    /// The row's line in the file, counting the header as line 1, for the review screen.
    public let line: Int
    public var date: FlexibleDate
    public var originText: String
    public var destinationText: String
    /// IATA or ICAO code pulled out of the airport column, where there was one.
    public var originCode: String?
    public var destinationCode: String?
    public var airline: String?
    public var flightNumber: String?
    public var aircraft: String?
    public var registration: String?
    public var seat: String?
    public var travelClass: String?
    public var purpose: TripPurpose?
    public var notes: String?
    /// The times as the file wrote them. Where the file named a zone for one, its
    /// offset is in `timeOffsets`, and the time is moved to the airport's own clock
    /// once the airport is known.
    public var times: LegTimes
    public var timeOffsets = LegTimeOffsets()
    /// The flight time the file states, if it has a column for it.
    public var durationMinutes: Int?
    /// Flighty records cancelled flights; they were never flown, so they are shown in
    /// the review but not imported.
    public var isCancelled = false
    /// Anything about the row the user should look at before importing it.
    public var problems: [String]
}

/// The UTC offset, in minutes, written beside each of a row's times, where one was.
public struct LegTimeOffsets: Hashable, Sendable {
    public var scheduledDeparture: Int?
    public var scheduledArrival: Int?
    public var actualDeparture: Int?
    public var actualArrival: Int?

    public init() {}
}

/// The file formats the importer recognises by their header row (R-LOG-8, Q-8).
public enum FlightLogFormat: String, Sendable, CaseIterable {
    case flighty
    case myFlightradar24
    case openFlights
    /// Any CSV whose header names a date and two airport columns.
    case generic

    public var displayName: String {
        switch self {
        case .flighty: "Flighty"
        case .myFlightradar24: "myFlightradar24"
        case .openFlights: "OpenFlights"
        case .generic: "Flight list (CSV)"
        }
    }
}

/// Reads flight histories exported from other apps (R-LOG-8, R-JLOG-7).
///
/// Q-8 is resolved here (decision D-16): the first formats are Flighty, myFlightradar24
/// and OpenFlights, which between them cover most people's flight logs, plus any CSV
/// whose header names a date and two airport columns. Columns are found by name, not
/// position, so a reordered or extended export still reads. Airports are matched by
/// code against the bundled database afterwards; nothing here touches the network.
public enum FlightLogImport {
    public enum Failure: Error, Equatable, CustomStringConvertible, LocalizedError {
        case missingColumns([String])
        case noFlights

        public var errorDescription: String? {
            description
        }

        public var description: String {
            switch self {
            case let .missingColumns(names):
                "This file has no \(names.joined(separator: " or ")) column, so it does not "
                    + "look like a flight list."
            case .noFlights:
                "The file has a header but no flights in it."
            }
        }
    }

    // Column names across the formats, normalised by `CSVTable.normalise`.
    static let dateColumns = ["date", "flightdate", "departuredate", "day"]
    static let fromColumns = [
        "from",
        "origin",
        "departure",
        "departureairport",
        "fromairport",
        "dep",
    ]
    static let toColumns = ["to", "destination", "arrival", "arrivalairport", "toairport", "arr"]
    static let airlineColumns = ["airline", "carrier", "operator", "airlinename"]
    static let flightColumns = ["flight", "flightnumber", "flightno", "flightnum"]
    static let aircraftColumns = [
        "aircraft",
        "aircrafttype",
        "aircrafttypename",
        "plane",
        "equipment",
    ]
    static let registrationColumns = ["registration", "tailnumber", "tail", "reg"]
    static let seatColumns = ["seat", "seatnumber"]
    static let classColumns = ["class", "cabinclass", "flightclass", "cabin"]
    static let reasonColumns = ["reason", "flightreason", "purpose"]
    static let notesColumns = ["notes", "note", "comment", "comments"]
    static let departureColumns = [
        "gatedeparturescheduled", "takeoffscheduled", "deptime", "departuretime",
        "scheduleddeparture",
    ]
    static let actualDepartureColumns = ["gatedepartureactual", "takeoffactual", "actualdeparture"]
    static let arrivalColumns = [
        "gatearrivalscheduled", "landingscheduled", "arrtime", "arrivaltime", "scheduledarrival",
    ]
    static let actualArrivalColumns = ["gatearrivalactual", "landingactual", "actualarrival"]
    static let durationColumns = ["duration", "flighttime", "flightduration", "blocktime"]
    static let cancelledColumns = ["canceled", "cancelled"]
    static let divertedColumns = ["divertedto", "diverted", "diversion"]

    public static func detectFormat(_ table: CSVTable) -> FlightLogFormat {
        let names = Set(table.header.map(CSVTable.normalise))
        if names.contains("flightflightyid") || names.contains("gatedeparturescheduled") {
            return .flighty
        }
        if names.contains("depid") || names.contains("airlineid") && names.contains("seattype") {
            return .myFlightradar24
        }
        if names.contains("fromoid") || names.contains("planeid") {
            return .openFlights
        }
        return .generic
    }

    // One column mapping per field, read side by side.
    // swiftlint:disable function_body_length
    /// Parses a file into rows ready for matching.
    ///
    /// `dayFirst` settles dates like 03/04/2021 when nothing in the file does: a value
    /// above 12 in either position decides it for the whole file, and only a file where
    /// every date is ambiguous falls back to the device's convention.
    public static func parse(
        _ data: Data,
        dayFirst: Bool
    ) throws -> (format: FlightLogFormat, rows: [FlightImportRow]) {
        let table = try CSVTable(data: data)
        let format = detectFormat(table)
        guard let dateColumn = table.column(dateColumns) else {
            throw Failure.missingColumns(["date"])
        }
        guard let fromColumn = table.column(fromColumns),
              let toColumn = table.column(toColumns) else {
            throw Failure.missingColumns(["from", "to"])
        }

        let resolvedDayFirst = DateText.dayFirst(
            in: table.rows.compactMap { table.value($0, dateColumn) },
            fallback: dayFirst
        )

        var rows: [FlightImportRow] = []
        for (index, raw) in table.rows.enumerated() {
            let originText = table.value(raw, fromColumn) ?? ""
            let scheduledDestination = table.value(raw, toColumn) ?? ""
            if originText.isEmpty, scheduledDestination.isEmpty {
                continue
            }
            var problems: [String] = []
            var notes = table.value(raw, table.column(notesColumns))

            // A diverted flight landed somewhere else, and that is where the user went.
            let diversion = table.value(raw, table.column(divertedColumns))
                .flatMap { AirportCode.extract(from: $0) != nil ? $0 : nil }
            let destinationText = diversion ?? scheduledDestination
            if diversion != nil {
                let note = "Diverted; scheduled to \(scheduledDestination)."
                notes = notes.map { "\($0)\n\(note)" } ?? note
            }
            let isCancelled = table.value(raw, table.column(cancelledColumns))
                .map(Self.isTrue) ?? false
            let dateText = table.value(raw, dateColumn)
            let parsedDate = dateText.flatMap { DateText.parse($0, dayFirst: resolvedDayFirst) }
            if dateText != nil, parsedDate == nil {
                problems.append("The date \"\(dateText ?? "")\" could not be read.")
            }
            let day = parsedDate?.day
            let date: FlexibleDate = parsedDate.map { .day($0.day) } ?? .unknown

            func time(_ names: [String]) -> StampedTime? {
                table.value(raw, table.column(names)).flatMap { DateText.time(
                    $0,
                    on: day,
                    dayFirst: resolvedDayFirst
                ) }
            }
            let departure = time(departureColumns)
            let arrival = time(arrivalColumns)
            let actualDeparture = time(actualDepartureColumns)
            let actualArrival = time(actualArrivalColumns)
            var offsets = LegTimeOffsets()
            offsets.scheduledDeparture = departure?.offsetMinutes
            offsets.scheduledArrival = arrival?.offsetMinutes
            offsets.actualDeparture = actualDeparture?.offsetMinutes
            offsets.actualArrival = actualArrival?.offsetMinutes

            let originCode = AirportCode.extract(from: originText)
            let destinationCode = AirportCode.extract(from: destinationText)
            if originCode == nil {
                problems.append("No airport code found in \"\(originText)\".")
            }
            if destinationCode == nil {
                problems.append("No airport code found in \"\(destinationText)\".")
            }

            rows.append(
                FlightImportRow(
                    line: index + 2,
                    date: date,
                    originText: originText,
                    destinationText: destinationText,
                    originCode: originCode,
                    destinationCode: destinationCode,
                    airline: table.value(raw, table.column(airlineColumns)),
                    flightNumber: table.value(raw, table.column(flightColumns)),
                    aircraft: table.value(raw, table.column(aircraftColumns)),
                    registration: table.value(raw, table.column(registrationColumns)),
                    seat: table.value(raw, table.column(seatColumns)),
                    travelClass: travelClass(
                        table.value(raw, table.column(classColumns)),
                        format: format
                    ),
                    purpose: purpose(table.value(raw, table.column(reasonColumns))),
                    notes: notes,
                    times: LegTimes(
                        scheduledDeparture: departure?.time,
                        scheduledArrival: arrival?.time,
                        actualDeparture: actualDeparture?.time,
                        actualArrival: actualArrival?.time
                    ),
                    timeOffsets: offsets,
                    durationMinutes: table.value(raw, table.column(durationColumns))
                        .flatMap(DateText.durationMinutes),
                    isCancelled: isCancelled,
                    problems: problems
                )
            )
        }
        guard !rows.isEmpty else { throw Failure.noFlights }
        return (format, rows)
    }

    // swiftlint:enable function_body_length

    // One case per documented class code.
    // swiftlint:disable cyclomatic_complexity
    /// Cabin classes as words. OpenFlights writes a letter and myFlightradar24 a number;
    /// those codes are mapped where their meaning is documented and kept as-is otherwise.
    static func travelClass(_ text: String?, format: FlightLogFormat) -> String? {
        guard let text else { return nil }
        let lowered = text.lowercased()
        switch format {
        case .openFlights:
            switch lowered {
            case "y": return "Economy"
            case "p": return "Premium economy"
            case "c": return "Business"
            case "f": return "First"
            default: break
            }
        case .myFlightradar24:
            switch lowered {
            case "1": return "Economy"
            case "2": return "Business"
            case "3": return "First"
            case "4": return "Premium economy"
            case "5": return nil // "Private"
            default: break
            }
        case .flighty, .generic:
            break
        }
        return text
    }

    // swiftlint:enable cyclomatic_complexity

    /// A yes in any of the ways a spreadsheet writes one.
    static func isTrue(_ text: String) -> Bool {
        ["true", "yes", "y", "1"].contains(text.trimmingCharacters(in: .whitespaces).lowercased())
    }

    static func purpose(_ text: String?) -> TripPurpose? {
        guard let lowered = text?.lowercased() else { return nil }
        if lowered.hasPrefix("b") || lowered.contains("work") || lowered == "2" {
            return .work
        }
        if lowered.hasPrefix("l") || lowered.contains("personal") || lowered == "1" {
            return .leisure
        }
        return nil
    }
}
