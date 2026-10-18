import Foundation
import SQLite3

public enum SQLiteError: Error, CustomStringConvertible {
    case cannotOpen(path: String, message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(message: String)
    case typeMismatch(column: Int32, expected: String)

    public var description: String {
        switch self {
        case let .cannotOpen(path, message):
            "Cannot open database at \(path): \(message)"
        case let .prepareFailed(sql, message):
            "Cannot prepare statement: \(message)\nSQL: \(sql)"
        case let .stepFailed(message):
            "Query failed: \(message)"
        case let .typeMismatch(column, expected):
            "Column \(column) is not \(expected)"
        }
    }
}

/// A read-only SQLite connection.
///
/// Deliberately thin: open, prepare, bind, step. The app needs prepared statements and
/// FTS5 and nothing more, so this stands in for a database library and keeps the build
/// free of third-party code (decision D-1). It is not `Sendable` — a connection is
/// used from inside one actor.
final class SQLiteConnection {
    private let handle: OpaquePointer

    /// Opens a file read-only. Fails rather than creating a database, so a missing
    /// bundled resource is a loud error instead of an empty app.
    init(readOnlyPath path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)

        guard result == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "code \(result)"
            if let handle {
                sqlite3_close_v2(handle)
            }
            throw SQLiteError.cannotOpen(path: path, message: message)
        }
        self.handle = opened
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    var lastErrorMessage: String {
        String(cString: sqlite3_errmsg(handle))
    }

    /// Runs a query and maps each row.
    ///
    /// Values are bound as parameters, never interpolated, so a search for `"` or
    /// `; DROP` is just text.
    func query<T>(
        _ sql: String,
        parameters: [SQLiteValue] = [],
        row decode: (SQLiteRow) throws -> T
    ) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw SQLiteError.prepareFailed(sql: sql, message: lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in parameters.enumerated() {
            value.bind(to: statement, at: Int32(offset + 1))
        }

        var results: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                try results.append(decode(SQLiteRow(statement: statement)))
            case SQLITE_DONE:
                return results
            default:
                throw SQLiteError.stepFailed(message: lastErrorMessage)
            }
        }
    }

    func queryOne<T>(
        _ sql: String,
        parameters: [SQLiteValue] = [],
        row decode: (SQLiteRow) throws -> T
    ) throws -> T? {
        try query(sql, parameters: parameters, row: decode).first
    }
}

/// A value bound to a statement parameter.
enum SQLiteValue {
    case text(String)
    case integer(Int64)
    case double(Double)
    case null

    func bind(to statement: OpaquePointer, at index: Int32) {
        switch self {
        case let .text(value):
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        case let .integer(value):
            sqlite3_bind_int64(statement, index, value)
        case let .double(value):
            sqlite3_bind_double(statement, index, value)
        case .null:
            sqlite3_bind_null(statement, index)
        }
    }
}

/// `SQLITE_TRANSIENT` is a function pointer cast that the Swift importer does not
/// surface, so it is rebuilt here. Without it, bound strings can dangle.
private let SQLITE_TRANSIENT = unsafeBitCast(
    -1 as Int,
    to: sqlite3_destructor_type.self
)

/// One row of a result set, read by column index.
struct SQLiteRow {
    let statement: OpaquePointer

    func isNull(_ column: Int32) -> Bool {
        sqlite3_column_type(statement, column) == SQLITE_NULL
    }

    func string(_ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    func requiredString(_ column: Int32) throws -> String {
        guard let value = string(column) else {
            throw SQLiteError.typeMismatch(column: column, expected: "text")
        }
        return value
    }

    func int64(_ column: Int32) -> Int64? {
        isNull(column) ? nil : sqlite3_column_int64(statement, column)
    }

    func requiredInt64(_ column: Int32) throws -> Int64 {
        guard let value = int64(column) else {
            throw SQLiteError.typeMismatch(column: column, expected: "integer")
        }
        return value
    }

    func int(_ column: Int32) -> Int? {
        int64(column).map(Int.init)
    }

    func bool(_ column: Int32) -> Bool {
        (int64(column) ?? 0) != 0
    }

    func double(_ column: Int32) -> Double? {
        isNull(column) ? nil : sqlite3_column_double(statement, column)
    }
}
