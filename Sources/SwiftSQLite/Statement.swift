import CSQLite

/// A prepared statement, for running one SQL statement many times with
/// different arguments. It lives for the `prepare` closure that hands it out,
/// on the connection's thread: used once that closure has returned, it stops
/// the program (rather than race the thread that has the connection now).
public final class Statement {
    let handle: OpaquePointer
    private let connection: OpaquePointer
    /// The SQL it was prepared from.
    public let sql: String
    /// Whether the `prepare` closure that handed it out is still running.
    private var live = true

    init(connection: OpaquePointer, sql: String) throws {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(connection, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw SQLiteError.last(connection, code: code, sql: sql)
        }
        handle = statement
        self.connection = connection
        self.sql = sql
    }

    deinit { sqlite3_finalize(handle) }

    /// Ends its use: the `prepare` closure has returned.
    func invalidate() {
        live = false
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    private func checkLive() {
        precondition(live, "a SwiftSQLite Statement or Row was used outside the closure that handed it out")
    }

    /// How many `?` parameters it takes.
    public var parameterCount: Int {
        checkLive()
        return Int(sqlite3_bind_parameter_count(handle))
    }

    /// How many columns each row has.
    public var columnCount: Int {
        checkLive()
        return Int(sqlite3_column_count(handle))
    }

    /// The names of its columns.
    public var columnNames: [String] {
        checkLive()
        return (0..<sqlite3_column_count(handle)).map { String(cString: sqlite3_column_name(handle, $0)) }
    }

    /// Resets it and binds `arguments` to its parameters, the first to `?1`.
    public func bind(_ arguments: any SQLiteBindable...) throws {
        try bind(arguments: arguments)
    }

    /// Resets it and binds `arguments` to its parameters, the first to `?1`.
    /// The count must be the statement's parameter count.
    public func bind(arguments: [any SQLiteBindable]) throws {
        checkLive()
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        let expected = Int(sqlite3_bind_parameter_count(handle))
        guard arguments.count == expected else {
            throw SQLiteError(
                extendedCode: SQLITE_RANGE,
                message: "\(arguments.count) arguments for \(expected) parameters", sql: sql)
        }
        for (offset, argument) in arguments.enumerated() {
            try bind(argument.sqliteValue, at: Int32(offset + 1))
        }
    }

    /// Binds `value` to the parameter named `name` (`:name`, `@name` or
    /// `$name`, its prefix included), leaving the others as they are.
    public func bind(_ value: any SQLiteBindable, named name: String) throws {
        checkLive()
        let index = sqlite3_bind_parameter_index(handle, name)
        guard index > 0 else {
            throw SQLiteError(extendedCode: SQLITE_RANGE, message: "no parameter named \(name)", sql: sql)
        }
        try bind(value.sqliteValue, at: index)
    }

    private func bind(_ value: SQLiteValue, at index: Int32) throws {
        let code: Int32
        switch value {
        case .null:
            code = sqlite3_bind_null(handle, index)
        case .integer(let integer):
            code = sqlite3_bind_int64(handle, index, integer)
        case .real(let real):
            code = sqlite3_bind_double(handle, index, real)
        case .text(let text):
            code = sqlite3_bind_text64(handle, index, text, UInt64(text.utf8.count), csqlite_transient(), UInt8(SQLITE_UTF8))
        case .blob(let bytes):
            code = bytes.withUnsafeBytes { buffer in
                // A zero-length blob is a blob, not NULL: SQLite needs a
                // non-null pointer for it.
                buffer.baseAddress.map { sqlite3_bind_blob64(handle, index, $0, UInt64(buffer.count), csqlite_transient()) }
                    ?? sqlite3_bind_zeroblob(handle, index, 0)
            }
        }
        guard code == SQLITE_OK else { throw SQLiteError.last(connection, code: code, sql: sql) }
    }

    /// The next row, or nil once there are none. The row is valid until the
    /// next step.
    public func step() throws -> Row? {
        checkLive()
        switch sqlite3_step(handle) {
        case SQLITE_ROW:
            return Row(statement: self)
        case SQLITE_DONE:
            return nil
        case let code:
            let error = SQLiteError.last(connection, code: code, sql: sql)
            sqlite3_reset(handle)
            throw error
        }
    }

    /// Runs it to the end, ignoring any rows; how many rows it changed.
    @discardableResult
    public func run() throws -> Int {
        while try step() != nil {}
        return Int(sqlite3_changes64(connection))
    }

    /// Runs it to the end, each row read by `read`.
    public func rows<T>(_ read: (Row) throws -> T) throws -> [T] {
        var out: [T] = []
        while let row = try step() {
            out.append(try read(row))
        }
        return out
    }

    /// Back to its first row, keeping its arguments.
    public func reset() {
        checkLive()
        sqlite3_reset(handle)
    }

    // MARK: Columns, for Row

    fileprivate func type(_ column: Int32) -> Int32 {
        checkLive()
        return sqlite3_column_type(handle, column)
    }
}

/// A row of a statement's result, read by column: by its index (from 0) as
/// a typed value, or as an `SQLiteValue` by index or name. Valid until its
/// statement steps again.
public struct Row {
    let statement: Statement

    /// How many columns it has.
    public var count: Int { statement.columnCount }

    /// The names of its columns.
    public var columnNames: [String] { statement.columnNames }

    /// The index of the column named `name`, or nil.
    public func index(of name: String) -> Int? {
        statement.columnNames.firstIndex(of: name)
    }

    /// The column's value as SQLite stores it.
    public func value(_ column: Int) -> SQLiteValue {
        let index = Int32(column)
        switch statement.type(index) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(statement.handle, index))
        case SQLITE_FLOAT: return .real(sqlite3_column_double(statement.handle, index))
        case SQLITE_TEXT: return text(column).map(SQLiteValue.text) ?? .null
        case SQLITE_BLOB: return .blob(blob(column) ?? [])
        default: return .null
        }
    }

    /// The value of the column named `name`, or nil when it has none.
    public subscript(_ name: String) -> SQLiteValue? {
        index(of: name).map(value)
    }

    public func isNull(_ column: Int) -> Bool {
        statement.type(Int32(column)) == SQLITE_NULL
    }

    /// The column as an integer, by SQLite's conversions (NULL is 0).
    public func int64(_ column: Int) -> Int64 {
        _ = statement.type(Int32(column))
        return sqlite3_column_int64(statement.handle, Int32(column))
    }

    /// The column as an integer, by SQLite's conversions (NULL is 0).
    public func int(_ column: Int) -> Int { Int(truncatingIfNeeded: int64(column)) }

    /// The column as a real, by SQLite's conversions (NULL is 0).
    public func double(_ column: Int) -> Double {
        _ = statement.type(Int32(column))
        return sqlite3_column_double(statement.handle, Int32(column))
    }

    /// The column as a boolean: nonzero is true.
    public func bool(_ column: Int) -> Bool { int64(column) != 0 }

    /// The column as text (UTF-8), or nil for NULL.
    public func text(_ column: Int) -> String? {
        let index = Int32(column)
        guard statement.type(index) != SQLITE_NULL, let bytes = sqlite3_column_text(statement.handle, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement.handle, index))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }

    /// The column's bytes, or nil for NULL.
    public func blob(_ column: Int) -> [UInt8]? {
        let index = Int32(column)
        guard statement.type(index) != SQLITE_NULL else { return nil }
        let pointer = sqlite3_column_blob(statement.handle, index)
        let count = Int(sqlite3_column_bytes(statement.handle, index))
        guard let pointer, count > 0 else { return [] }
        return Array(UnsafeRawBufferPointer(start: pointer, count: count))
    }
}

// Neither may leave the thread that has the connection.
@available(*, unavailable)
extension Statement: Sendable {}

@available(*, unavailable)
extension Row: Sendable {}
