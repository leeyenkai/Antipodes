import Foundation

/// Writes RFC 4180 CSV.
///
/// Place names carry commas, quotes and newlines (`Washington, D.C.`,
/// `L'Anse aux Meadows`), so quoting is not optional — an export that breaks on them
/// is an export the user cannot re-import.
public struct CSVWriter {
    public private(set) var rows: [[String]] = []

    public init(header: [String]) {
        rows.append(header)
    }

    public mutating func append(_ values: [String?]) {
        rows.append(values.map { $0 ?? "" })
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
