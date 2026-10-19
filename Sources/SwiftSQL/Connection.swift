import CSwiftSQL

/// How a transaction takes its locks: SQLite's BEGIN DEFERRED (on the first
/// read or write), IMMEDIATE (a write lock at once) or EXCLUSIVE.
public enum TransactionKind: String, Sendable {
    case deferred = "DEFERRED"
    case immediate = "IMMEDIATE"
    case exclusive = "EXCLUSIVE"
}

/// A database's connection, for the closure that has it: `Database`'s
/// `withConnection` and `transaction` hand it out, holding the database's
/// lock until the closure returns. What it runs runs in that order, with
/// nothing from another thread between.
public struct Connection {
    let handle: OpaquePointer
    /// Whether the closure that has it is still running: used after it
    /// returns, it stops the program rather than run without the lock.
    let scope: Scope

    final class Scope {
        var live = true
    }

    private func check() {
        precondition(scope.live, "a SwiftSQL Connection was used outside the closure that handed it out")
    }

    /// Runs `sql`, one statement or several separated by semicolons, with no
    /// arguments (a schema, a pragma).
    public func execute(_ sql: String) throws {
        check()
        var message: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &message)
        defer { sqlite3_free(message) }
        guard code == SQLITE_OK else {
            let error = SQLiteError.last(handle, code: code, sql: sql)
            throw message.map { SQLiteError(extendedCode: error.extendedCode, message: String(cString: $0), sql: sql) } ?? error
        }
    }

    /// Runs one statement with `arguments` bound to its parameters, the
    /// first to `?1`; how many rows it changed.
    @discardableResult
    public func run(_ sql: String, _ arguments: any SQLiteBindable...) throws -> Int {
        try run(sql, arguments: arguments)
    }

    @discardableResult
    public func run(_ sql: String, arguments: [any SQLiteBindable]) throws -> Int {
        try prepare(sql) { statement in
            try statement.bind(arguments: arguments)
            return try statement.run()
        }
    }

    /// Runs one statement with `arguments` and reads each row with `row`.
    public func query<T>(_ sql: String, _ arguments: any SQLiteBindable..., row: (Row) throws -> T) throws -> [T] {
        try query(sql, arguments: arguments, row: row)
    }

    public func query<T>(_ sql: String, arguments: [any SQLiteBindable], row: (Row) throws -> T) throws -> [T] {
        try prepare(sql) { statement in
            try statement.bind(arguments: arguments)
            return try statement.rows(row)
        }
    }

    /// Prepares `sql` for `body`, to run it as many times as it needs; the
    /// statement is finalized when `body` returns.
    @discardableResult
    public func prepare<T>(_ sql: String, _ body: (Statement) throws -> T) throws -> T {
        check()
        let statement = try Statement(connection: handle, sql: sql)
        defer { statement.invalidate() }
        return try body(statement)
    }

    /// Runs `body` in a transaction: committed when it returns, rolled back
    /// when it throws. Inside another transaction it is a savepoint of it,
    /// released or rolled back to the same way.
    @discardableResult
    public func transaction<T>(_ kind: TransactionKind = .deferred, _ body: (Connection) throws -> T) throws -> T {
        check()
        if isInTransaction {
            try execute("SAVEPOINT swift_sql")
            do {
                let result = try body(self)
                try execute("RELEASE swift_sql")
                return result
            } catch {
                try? execute("ROLLBACK TO swift_sql")
                try? execute("RELEASE swift_sql")
                throw error
            }
        }
        try execute("BEGIN \(kind.rawValue)")
        do {
            let result = try body(self)
            try execute("COMMIT")
            return result
        } catch {
            if isInTransaction { try? execute("ROLLBACK") }
            throw error
        }
    }

    /// Whether a transaction is open.
    public var isInTransaction: Bool {
        check()
        return sqlite3_get_autocommit(handle) == 0
    }

    /// The rowid of the latest successful INSERT.
    public var lastInsertRowID: Int64 {
        check()
        return sqlite3_last_insert_rowid(handle)
    }

    /// How many rows the latest INSERT, UPDATE or DELETE changed.
    public var changes: Int {
        check()
        return Int(sqlite3_changes64(handle))
    }

    /// The database's contents as bytes (`schema`, "main" by default): what
    /// `Database(serialized:)` opens again.
    public func serialize(schema: String = "main") throws -> [UInt8] {
        check()
        var size: sqlite3_int64 = 0
        guard let bytes = sqlite3_serialize(handle, schema, &size, 0) else {
            // An empty database serializes to nothing.
            if size == 0 { return [] }
            throw SQLiteError(extendedCode: SQLITE_NOMEM, message: "could not serialize \(schema)")
        }
        defer { sqlite3_free(bytes) }
        return Array(UnsafeBufferPointer(start: bytes, count: Int(size)))
    }

    /// The connection's `sqlite3` pointer, for what this package does not
    /// wrap (`import CSwiftSQL`). Valid for `body` only.
    public func withUnsafeHandle<T>(_ body: (OpaquePointer) throws -> T) rethrows -> T {
        check()
        return try body(handle)
    }
}

// The connection stays on the thread that holds the database's lock.
@available(*, unavailable)
extension Connection: Sendable {}
