import CSQLite

/// A failed SQLite call: its result code (extended, as the connection
/// reports them), SQLite's message, and the SQL it was running, if any.
public struct SQLiteError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The extended result code (`SQLITE_CONSTRAINT_UNIQUE`, …).
    public let extendedCode: Int32
    /// SQLite's message for it.
    public let message: String
    /// The statement it came from.
    public let sql: String?

    public init(extendedCode: Int32, message: String, sql: String? = nil) {
        self.extendedCode = extendedCode
        self.message = message
        self.sql = sql
    }

    /// The primary result code (`SQLITE_CONSTRAINT`, `SQLITE_BUSY`, …).
    public var code: Int32 { extendedCode & 0xFF }

    /// Another connection held a lock past the busy timeout.
    public var isBusy: Bool { code == SQLITE_BUSY || code == SQLITE_LOCKED }
    /// A constraint failed (unique, not null, foreign key, check).
    public var isConstraint: Bool { code == SQLITE_CONSTRAINT }
    /// The call was interrupted: its task was cancelled.
    public var isInterrupted: Bool { code == SQLITE_INTERRUPT }

    public var description: String {
        let name = String(cString: sqlite3_errstr(extendedCode))
        let what = sql.map { " in \"\($0)\"" } ?? ""
        return "SQLite error \(extendedCode) (\(name)): \(message)\(what)"
    }

    /// The connection's latest error.
    static func last(_ handle: OpaquePointer, code: Int32, sql: String? = nil) -> SQLiteError {
        let extended = sqlite3_extended_errcode(handle)
        // The connection's error is this call's unless the code says otherwise
        // (a code from a call that does not set the connection's error).
        let matches = extended & 0xFF == code & 0xFF
        return SQLiteError(
            extendedCode: matches ? extended : code,
            message: matches ? String(cString: sqlite3_errmsg(handle)) : String(cString: sqlite3_errstr(code)),
            sql: sql)
    }

    /// The use of a closed database.
    static func closed(_ sql: String? = nil) -> SQLiteError {
        SQLiteError(extendedCode: SQLITE_MISUSE, message: "the database is closed", sql: sql)
    }
}
