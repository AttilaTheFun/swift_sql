import CSQLite

/// An SQLite database: one connection, shared by every thread, task and actor
/// that has the `Database`. Each call has the connection to itself, the
/// calls made one after another behind the database's lock, so what one
/// closure runs (a transaction, a prepared statement's rows) runs with
/// nothing from another caller between.
///
/// Its methods run on the caller's thread (SQLite's calls are quick, and the
/// main actor may make them); `perform` runs a closure with the connection
/// off the caller's executor, its task's cancellation stopping the statement
/// under way.
public final class Database: @unchecked Sendable {
    // Sendable by construction: `handle` is used only inside `lock`
    // (`withConnection`), and set to nil there when the database closes;
    // `interrupt` reads it under `handleLock`, which `close` takes as well,
    // so an interrupt never reaches a connection being closed.
    private let lock = RecursiveLock()
    private let handleLock = RecursiveLock()
    private var handle: OpaquePointer?

    /// Where it is: a file's path, or ":memory:".
    public let path: String

    /// How it is opened (SQLite's SQLITE_OPEN_* flags).
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int32
        public init(rawValue: Int32) { self.rawValue = rawValue }

        public static let readOnly = Options(rawValue: SQLITE_OPEN_READONLY)
        public static let readWrite = Options(rawValue: SQLITE_OPEN_READWRITE)
        /// Created if it does not exist (with `readWrite`).
        public static let create = Options(rawValue: SQLITE_OPEN_CREATE)
        /// `path` is a `file:` URI.
        public static let uri = Options(rawValue: SQLITE_OPEN_URI)
    }

    /// Opens the database at `path` (":memory:" for one in memory).
    /// `busyTimeout`: how long a call waits on another connection's lock
    /// before it fails as busy.
    public init(path: String, options: Options = [.readWrite, .create], busyTimeout: Duration? = .seconds(5)) throws {
        self.path = path
        var connection: OpaquePointer?
        let code = sqlite3_open_v2(path, &connection, options.rawValue, nil)
        guard code == SQLITE_OK, let connection else {
            let error = connection.map { SQLiteError.last($0, code: code) }
                ?? SQLiteError(extendedCode: code, message: String(cString: sqlite3_errstr(code)))
            sqlite3_close_v2(connection)
            throw error
        }
        sqlite3_extended_result_codes(connection, 1)
        if let busyTimeout {
            let (seconds, attoseconds) = busyTimeout.components
            let milliseconds = seconds * 1000 + attoseconds / 1_000_000_000_000_000
            sqlite3_busy_timeout(connection, Int32(clamping: milliseconds))
        }
        handle = connection
    }

    /// A database in memory, gone when it closes.
    public static func inMemory() throws -> Database {
        try Database(path: ":memory:")
    }

    /// A database in memory holding `bytes`, which `serialize()` made.
    public convenience init(serialized bytes: [UInt8]) throws {
        try self.init(path: ":memory:")
        try withConnection { connection in
            try connection.withUnsafeHandle { handle in
                // SQLite owns the buffer from here: it frees it when the
                // database closes, or when it grows the database.
                guard let buffer = sqlite3_malloc64(UInt64(max(bytes.count, 1))) else {
                    throw SQLiteError(extendedCode: SQLITE_NOMEM, message: "no memory for \(bytes.count) bytes")
                }
                bytes.withUnsafeBytes { source in
                    if let base = source.baseAddress { buffer.copyMemory(from: base, byteCount: source.count) }
                }
                let flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE)
                let code = sqlite3_deserialize(
                    handle, "main", buffer.assumingMemoryBound(to: UInt8.self),
                    sqlite3_int64(bytes.count), sqlite3_int64(bytes.count), flags)
                guard code == SQLITE_OK else { throw SQLiteError.last(handle, code: code) }
            }
        }
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    /// Closes it; every later call throws. Closing again does nothing.
    public func close() {
        lock.withLock {
            handleLock.withLock {
                if let handle { sqlite3_close_v2(handle) }
                handle = nil
            }
        }
    }

    /// Runs `body` with the connection, every other caller waiting meanwhile.
    @discardableResult
    public func withConnection<T>(_ body: (Connection) throws -> T) throws -> T {
        try lock.withLock {
            guard let handle else { throw SQLiteError.closed() }
            let connection = Connection(handle: handle, scope: Connection.Scope())
            defer { connection.scope.live = false }
            return try body(connection)
        }
    }

    /// Stops the statement under way, which then throws an interrupted
    /// error (`SQLiteError.isInterrupted`): for a call another thread wants
    /// stopped (`perform` stops when its task is cancelled).
    public func interrupt() {
        handleLock.withLock {
            if let handle { sqlite3_interrupt(handle) }
        }
    }

    // MARK: Synchronous

    /// Runs `sql`, one statement or several, with no arguments.
    public func execute(_ sql: String) throws {
        try withConnection { try $0.execute(sql) }
    }

    /// Runs one statement with `arguments`; how many rows it changed.
    @discardableResult
    public func run(_ sql: String, _ arguments: any SQLiteBindable...) throws -> Int {
        try run(sql, arguments: arguments)
    }

    @discardableResult
    public func run(_ sql: String, arguments: [any SQLiteBindable]) throws -> Int {
        try withConnection { try $0.run(sql, arguments: arguments) }
    }

    /// Runs one statement with `arguments`, each row read by `row`.
    public func query<T>(_ sql: String, _ arguments: any SQLiteBindable..., row: (Row) throws -> T) throws -> [T] {
        try query(sql, arguments: arguments, row: row)
    }

    public func query<T>(_ sql: String, arguments: [any SQLiteBindable], row: (Row) throws -> T) throws -> [T] {
        try withConnection { try $0.query(sql, arguments: arguments, row: row) }
    }

    /// Prepares `sql` for `body`, to run as many times as it needs.
    @discardableResult
    public func prepare<T>(_ sql: String, _ body: (Statement) throws -> T) throws -> T {
        try withConnection { try $0.prepare(sql, body) }
    }

    /// Runs `body` in a transaction: committed when it returns, rolled back
    /// when it throws.
    @discardableResult
    public func transaction<T>(_ kind: TransactionKind = .deferred, _ body: (Connection) throws -> T) throws -> T {
        try withConnection { try $0.transaction(kind, body) }
    }

    /// Its contents as bytes, for `Database(serialized:)`.
    public func serialize(schema: String = "main") throws -> [UInt8] {
        try withConnection { try $0.serialize(schema: schema) }
    }

    // MARK: Asynchronous

    /// Runs `body` with the connection off the caller's executor, for work
    /// that should not hold the caller's thread (a big query on the main
    /// actor's behalf). Cancelling the task stops what `body` runs: SQLite
    /// checks every thousand steps of its program (`sqlite3_progress_handler`),
    /// and a statement stopped so throws an interrupted error
    /// (`SQLiteError.isInterrupted`), as does a call cancelled before it had
    /// the connection.
    ///
    /// One entry point rather than an `async` twin of each method: Swift
    /// prefers an `async` overload inside an `async` function, so twins would
    /// make every synchronous call there need an `await`.
    @discardableResult
    public func perform<T: Sendable>(_ body: @escaping @Sendable (Connection) throws -> T) async throws -> T {
        try Task.checkCancellation()
        let flag = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: Task.currentPriority) { [self] in
                try self.withConnection { connection in
                    guard !flag.isCancelled else {
                        throw SQLiteError(extendedCode: SQLITE_INTERRUPT, message: "cancelled")
                    }
                    let context = Unmanaged.passUnretained(flag).toOpaque()
                    sqlite3_progress_handler(connection.handle, 1000, cancelledProgress, context)
                    defer { sqlite3_progress_handler(connection.handle, 0, nil, nil) }
                    return try body(connection)
                }
            }.value
        } onCancel: {
            flag.cancel()
        }
    }
}

/// Whether a `perform` call's task was cancelled, set from the task's
/// cancellation handler and read by SQLite's progress handler on the thread
/// running the call.
private final class CancellationFlag: @unchecked Sendable {
    private let lock = RecursiveLock()
    private var cancelled = false

    func cancel() { lock.withLock { cancelled = true } }
    var isCancelled: Bool { lock.withLock { cancelled } }
}

/// SQLite's progress handler for a `perform` call: nonzero stops the
/// statement (SQLITE_INTERRUPT) once its task is cancelled.
private let cancelledProgress: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = { context in
    guard let context else { return 0 }
    return Unmanaged<CancellationFlag>.fromOpaque(context).takeUnretainedValue().isCancelled ? 1 : 0
}
