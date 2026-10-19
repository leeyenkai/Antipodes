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
    public var times: LegTimes
    /// Anything about the row the user should look at before importing it.
    public var problems: [String]
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
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case missingColumns([String])
        case noFlights

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
            let destinationText = table.value(raw, toColumn) ?? ""
            if originText.isEmpty, destinationText.isEmpty {
                continue
            }
            var problems: [String] = []
            let dateText = table.value(raw, dateColumn)
            let parsedDate = dateText.flatMap { DateText.parse($0, dayFirst: resolvedDayFirst) }
            if dateText != nil, parsedDate == nil {
                problems.append("The date \"\(dateText ?? "")\" could not be read.")
            }
            let day = parsedDate?.day
            let date: FlexibleDate = parsedDate.map { .day($0.day) } ?? .unknown

            func time(_ names: [String]) -> LocalDateTime? {
                table.value(raw, table.column(names)).flatMap { DateText.time(
                    $0,
                    on: day,
                    dayFirst: resolvedDayFirst
                ) }
            }

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
                    notes: table.value(raw, table.column(notesColumns)),
                    times: LegTimes(
                        scheduledDeparture: time(departureColumns),
                        scheduledArrival: time(arrivalColumns),
                        actualDeparture: time(actualDepartureColumns),
                        actualArrival: time(actualArrivalColumns)
                    ),
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

/// A flight read from a file, matched to the bundled airports and ready to review.
public struct FlightImportCandidate: Hashable, Sendable, Identifiable {
    public enum Status: Hashable, Sendable {
        case ready
        /// One or both airports could not be matched; the user can pick them by hand.
        case needsAirport
        /// The same flight is already in the log.
        case duplicate
    }

    public var id: Int {
        row.line
    }

    public var row: FlightImportRow
    public var origin: PlaceReference?
    public var destination: PlaceReference?
    public var include: Bool

    public var status: Status {
        if origin == nil || destination == nil {
            return .needsAirport
        }
        return isDuplicate ? .duplicate : .ready
    }

    public var isDuplicate: Bool

    public init(
        row: FlightImportRow,
        origin: PlaceReference?,
        destination: PlaceReference?,
        isDuplicate: Bool
    ) {
        self.row = row
        self.origin = origin
        self.destination = destination
        self.isDuplicate = isDuplicate
        include = origin != nil && destination != nil && !isDuplicate
    }

    /// The leg this candidate becomes, once both airports are known.
    ///
    /// Exports that give only a clock time for arrival leave an overnight flight landing
    /// "before" it took off. Once both airports' zones are known that is detectable, and
    /// the only reading that makes sense is the next day — no flight lands before it
    /// leaves, and none takes a day — so the arrival moves forward one day.
    public var leg: JourneyLeg? {
        guard var leg = rawLeg else { return nil }
        if case let .failure(failure) = leg.duration, failure.reason == .arrivesBeforeDeparture {
            leg.times.scheduledArrival = leg.times.scheduledArrival?.nextDay
            leg.times.actualArrival = leg.times.actualArrival?.nextDay
        }
        return leg
    }

    private var rawLeg: JourneyLeg? {
        guard let origin, let destination else { return nil }
        return JourneyLeg(
            mode: .flight,
            origin: origin,
            destination: destination,
            date: row.date,
            purpose: row.purpose ?? .leisure,
            times: row.times,
            operatorName: row.airline,
            serviceNumber: row.flightNumber,
            vehicle: row.aircraft,
            registration: row.registration,
            travelClass: row.travelClass,
            seat: row.seat,
            notes: row.notes
        )
    }
}

public extension FlightLogImport {
    /// Matches every row's airports by code, and flags flights already in the log.
    ///
    /// `airport` looks a code up in the bundled database; it is a parameter so this
    /// stays testable without one.
    static func match(
        _ rows: [FlightImportRow],
        existing: [JourneyLeg],
        airport: @Sendable (String) async -> PlaceReference?
    ) async -> [FlightImportCandidate] {
        var cache: [String: PlaceReference?] = [:]
        func lookUp(_ code: String?) async -> PlaceReference? {
            guard let code else { return nil }
            if let cached = cache[code] {
                return cached
            }
            let found = await airport(code)
            cache[code] = found
            return found
        }

        let fingerprints = Set(existing.filter { $0.mode == .flight }.map(Fingerprint.init))
        var candidates: [FlightImportCandidate] = []
        for row in rows {
            let origin = await lookUp(row.originCode)
            let destination = await lookUp(row.destinationCode)
            var duplicate = false
            if let origin, let destination {
                let probe = JourneyLeg(
                    mode: .flight,
                    origin: origin,
                    destination: destination,
                    date: row.date,
                    serviceNumber: row.flightNumber
                )
                duplicate = fingerprints.contains(Fingerprint(probe))
            }
            candidates.append(
                FlightImportCandidate(
                    row: row,
                    origin: origin,
                    destination: destination,
                    isDuplicate: duplicate
                )
            )
        }
        return candidates
    }

    /// What makes two flights the same flight: the day, both ends, and the flight
    /// number where both sides have one.
    internal struct Fingerprint: Hashable {
        let date: FlexibleDate
        let origin: PlaceID
        let destination: PlaceID
        let flightNumber: String?

        init(_ leg: JourneyLeg) {
            date = leg.date
            origin = leg.origin.id
            destination = leg.destination.id
            flightNumber = leg.serviceNumber?.uppercased().filter { !$0.isWhitespace }
        }
    }
}
