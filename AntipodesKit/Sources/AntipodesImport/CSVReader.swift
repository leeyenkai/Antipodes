import Foundation

/// Reads RFC 4180 CSV, the counterpart of the exporter's `CSVWriter`.
///
/// Handles quoted fields with embedded commas, quotes and line breaks, both CRLF and LF
/// line endings, UTF-8 with or without a byte-order mark, UTF-16 with one (what Excel
/// writes as "Unicode text"), and the semicolon separator some spreadsheet exports use
/// in locales where the comma is the decimal mark.
public enum CSVReader {
    public enum Failure: Error, Equatable, CustomStringConvertible, LocalizedError {
        case notText
        case empty
        case unterminatedQuote(line: Int)

        public var errorDescription: String? {
            description
        }

        public var description: String {
            switch self {
            case .notText: "The file is not readable text."
            case .empty: "The file is empty."
            case let .unterminatedQuote(line):
                "A quoted field starting on line \(line) never ends."
            }
        }
    }

    /// Parses `data` into rows of fields.
    public static func rows(from data: Data) throws -> [[String]] {
        let bytes = [UInt8](data.prefix(2))
        let isUTF16 = bytes == [0xFF, 0xFE] || bytes == [0xFE, 0xFF]
        guard var text = (isUTF16 ? String(data: data, encoding: .utf16) : nil)
            ?? String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        else { throw Failure.notText }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return try rows(from: text)
    }

    // A character-at-a-time state machine reads best as one loop.
    // swiftlint:disable cyclomatic_complexity function_body_length
    public static func rows(from text: String) throws -> [[String]] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Failure.empty
        }
        let separator = detectSeparator(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var line = 1
        var quoteStartLine = 1
        var iterator = Array(text.unicodeScalars).makeIterator()
        var pending: Unicode.Scalar?

        func next() -> Unicode.Scalar? {
            if let scalar = pending {
                pending = nil
                return scalar
            }
            return iterator.next()
        }

        while let scalar = next() {
            if inQuotes {
                if scalar == "\"" {
                    if let following = next() {
                        if following == "\"" {
                            field.unicodeScalars.append("\"")
                        } else {
                            inQuotes = false
                            pending = following
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    if scalar == "\n" {
                        line += 1
                    }
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"" where field.allSatisfy(\.isWhitespace):
                // `a, "b, c"`: the space after the separator is not part of the field,
                // so the quote still opens it.
                field = ""
                inQuotes = true
                quoteStartLine = line
            case separator:
                row.append(field)
                field = ""
            case "\r":
                // CR is a line ending only before LF or on its own; either way the row
                // ends here and a following LF is swallowed.
                if let following = next(), following != "\n" {
                    pending = following
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                line += 1
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                line += 1
            default:
                field.unicodeScalars.append(scalar)
            }
        }
        if inQuotes {
            throw Failure.unterminatedQuote(line: quoteStartLine)
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        // Blank lines carry nothing.
        return rows
            .filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    // swiftlint:enable cyclomatic_complexity function_body_length

    /// Comma unless the header line has more semicolons than commas outside quotes.
    static func detectSeparator(_ text: String) -> Unicode.Scalar {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        var commas = 0
        var semicolons = 0
        var inQuotes = false
        for character in firstLine {
            if character == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if character == "," {
                    commas += 1
                } else if character == ";" {
                    semicolons += 1
                }
            }
        }
        return semicolons > commas ? ";" : ","
    }
}

/// A CSV file with a header row, read by column name.
public struct CSVTable: Sendable {
    public let header: [String]
    public let rows: [[String]]

    public init(data: Data) throws {
        let all = try CSVReader.rows(from: data)
        guard let first = all.first else { throw CSVReader.Failure.empty }
        header = first.map { $0.trimmingCharacters(in: .whitespaces) }
        rows = Array(all.dropFirst())
    }

    public init(header: [String], rows: [[String]]) {
        self.header = header
        self.rows = rows
    }

    /// The index of the first column whose normalised name is in `names`.
    public func column(_ names: [String]) -> Int? {
        let wanted = Set(names.map(Self.normalise))
        return header.firstIndex { wanted.contains(Self.normalise($0)) }
    }

    /// Lowercased, with spaces, underscores, dashes and brackets removed, so "Flight
    /// number", "flight_number" and "FlightNumber" all match.
    static func normalise(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public func value(_ row: [String], _ column: Int?) -> String? {
        guard let column, column < row.count else { return nil }
        let value = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
