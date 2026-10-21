import AntipodesCore
import Foundation

// The pieces that let the flight-log reader take any journey list (R-JLOG-7, R-LOG-8):
// a JSON array as well as a CSV, a mode per row, rail-log column names and distances.

public extension CSVTable {
    /// A JSON list of journeys read as a table: one column per key, one row per object.
    ///
    /// The list can be the whole file or the first array of objects inside it — an
    /// export's `{"journeys": [...]}` reads as well as a bare `[...]`. Nested values are
    /// left out; columns are found by name, so key order does not matter.
    init(json data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let records = Self.records(in: object), !records.isEmpty else {
            throw CSVReader.Failure.empty
        }
        var header: [String] = []
        var seen: Set<String> = []
        for record in records {
            for key in record.keys.sorted() where seen.insert(key).inserted {
                header.append(key)
            }
        }
        let rows = records.map { record in
            header.map { key -> String in
                switch record[key] {
                case let text as String: text
                case let number as NSNumber: number.stringValue
                default: ""
                }
            }
        }
        self.init(header: header, rows: rows)
    }

    private static func records(in object: Any) -> [[String: Any]]? {
        if let list = object as? [[String: Any]] {
            return list
        }
        if let dictionary = object as? [String: Any] {
            for key in dictionary.keys.sorted() {
                if let list = dictionary[key] as? [[String: Any]], !list.isEmpty {
                    return list
                }
            }
        }
        return nil
    }

    /// Whether the data looks like JSON rather than CSV: it opens with a bracket.
    static func looksLikeJSON(_ data: Data) -> Bool {
        guard let first = data.first(where: { !(" \t\r\n" as String).utf8.contains($0) })
        else { return false }
        // An opening square or curly bracket.
        return first == 0x5B || first == 0x7B
    }
}

public extension TravelMode {
    /// A mode from the words other apps and spreadsheets use for it, or `nil`.
    init?(importText text: String) {
        let word = text.lowercased().filter { $0.isLetter || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
        let table: [(TravelMode, Set<String>)] = [
            (.flight, Self.flightWords),
            (.rail, ["rail", "train", "railway", "sleeper", "night train", "high speed"]),
            (.cityTransit, Self.transitWords),
            (.coach, ["coach", "bus", "long distance bus", "intercity bus"]),
            (.ferry, ["ferry", "boat", "ship", "cruise", "sea"]),
            (.roadTrip, Self.roadWords),
            (.humanPowered, Self.humanWords),
            (.cableAndMountain, Self.cableWords),
        ]
        for (mode, words) in table where words.contains(word) {
            self = mode
            return
        }
        if let raw = TravelMode(rawValue: text.trimmingCharacters(in: .whitespaces)) {
            self = raw
            return
        }
        return nil
    }

    private static let flightWords: Set = ["flight", "fly", "plane", "air", "airplane", "aeroplane"]
    private static let transitWords: Set = [
        "tram", "metro", "subway", "underground", "tube", "light rail", "streetcar",
        "city transit", "transit", "local bus",
    ]
    private static let roadWords: Set = [
        "car", "drive", "driving", "road", "road trip", "motorbike", "motorcycle", "taxi",
    ]
    private static let humanWords: Set = [
        "walk", "walking", "hike", "hiking", "foot", "bike", "bicycle", "cycle", "cycling",
        "run",
    ]
    private static let cableWords: Set = [
        "cable car", "gondola", "funicular", "chairlift", "cog railway", "rack railway",
        "aerial tramway",
    ]
}

public extension FlightLogImport {
    /// Whether a file says each row's mode itself; one that does not is read as all
    /// one mode, which the user picks.
    static func statesModes(_ data: Data) -> Bool {
        let table = CSVTable.looksLikeJSON(data)
            ? try? CSVTable(json: data)
            : try? CSVTable(data: data)
        return table?.column(modeColumns) != nil
    }
}

extension FlightLogImport {
    static let modeColumns = [
        "mode", "type", "transport", "transportmode", "travelmode", "modeoftransport", "means",
    ]
    static let serviceColumns = [
        "train", "trainnumber", "service", "servicenumber", "headcode", "line",
    ]
    static let distanceKmColumns = ["distance", "distancekm", "km", "kilometres", "kilometers"]
    static let distanceMilesColumns = ["distancemi", "distancemiles", "miles", "mileage"]

    /// The distance a row states, in kilometres. A bare "distance" column is read as
    /// kilometres unless its value says miles.
    static func distanceKm(_ table: CSVTable, _ row: [String]) -> Double? {
        if let text = table.value(row, table.column(distanceMilesColumns)),
           let miles = number(in: text) {
            return miles * 1.609344
        }
        guard let text = table.value(row, table.column(distanceKmColumns)),
              let value = number(in: text) else { return nil }
        let lowered = text.lowercased()
        return lowered.contains("mi") && !lowered.contains("km") ? value * 1.609344 : value
    }

    /// The first number in a text such as "1,234.5 km".
    private static func number(in text: String) -> Double? {
        let digits = text.replacingOccurrences(of: ",", with: "")
            .prefix { $0.isNumber || $0 == "." }
        return Double(digits).flatMap { $0 > 0 ? $0 : nil }
    }
}
