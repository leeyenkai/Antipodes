import Foundation

/// Writes RFC 4180 CSV.
///
/// Place names carry commas, quotes and newlines (`Washington, D.C.`,
/// `L'Anse aux Meadows`), so quoting is not optional — an export that breaks on them
/// is an export the user cannot re-import.
///
/// Text a spreadsheet would read as a formula — a note carried in from another app's
/// file that starts `=HYPERLINK(` — is defused with a leading apostrophe, the usual
/// guard against CSV injection. Columns named in `numericColumns` are left alone,
/// because a longitude or a delay legitimately starts with a minus sign.
public struct CSVWriter {
    public private(set) var rows: [[String]] = []
    private let isNumeric: [Bool]

    public init(header: [String], numericColumns: Set<String> = []) {
        rows.append(header)
        isNumeric = header.map(numericColumns.contains)
    }

    public mutating func append(_ values: [String?]) {
        rows.append(values.enumerated().map { index, value in
            let text = value ?? ""
            let numeric = index < isNumeric.count && isNumeric[index]
            return numeric ? text : Self.defused(text)
        })
    }

    /// A cell a spreadsheet would run as a formula, made inert.
    static func defused(_ value: String) -> String {
        guard let first = value.unicodeScalars.first,
              ["=", "+", "-", "@", "\t", "\r"].contains(first) else { return value }
        return "'" + value
    }

    public func encoded() -> String {
        rows.map { row in
            row.map(Self.field).joined(separator: ",")
        }
        .joined(separator: "\r\n")
        + "\r\n"
    }

    public func data() -> Data {
        Data(encoded().utf8)
    }

    static func field(_ value: String) -> String {
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
            || value.hasPrefix(" ")
            || value.hasSuffix(" ")

        guard needsQuoting else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
