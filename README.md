# swift_sqlite

SQLite for Swift on every platform Swift runs on, as two modules:

- **CSQLite**: SQLite's C API. On Apple's platforms the system's SQLite
  (the SDK's `sqlite3.h`, `libsqlite3`); everywhere else (Linux, Android,
  Windows, WebAssembly) SQLite 3.53.4's amalgamation, vendored in
  `Sources/CSQLite/amalgamation` and built by `Sources/CSQLite/csqlite.c`
  with full-text search (FTS5). The options live in that one file, so SwiftPM
  and Bazel build the same SQLite.
- **SwiftSQLite**: a thin Swift layer over the C API: safe to share across
  threads, tasks and actors under Swift 6's strict concurrency checking,
  with typed binding and reading, transactions, prepared statements and
  cancellation. It is not an ORM: you write the SQL. It has no Foundation
  dependency.

```swift
import SwiftSQLite

let db = try Database(path: path)            // or Database.inMemory()
try db.execute("""
    CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, body TEXT NOT NULL, pinned INTEGER);
    """)
try db.run("INSERT INTO notes(body, pinned) VALUES (?, ?)", "Buy milk", true)

let bodies = try db.query("SELECT body FROM notes WHERE pinned = ?", true) { row in row.text(0) ?? "" }

try db.transaction { tx in
    try tx.run("DELETE FROM notes WHERE pinned = ?", false)
    try tx.run("UPDATE notes SET pinned = 0")
}

// Off the caller's executor; cancelling the task stops the statement.
let count = try await db.perform { connection in
    try connection.query("SELECT count(*) FROM notes") { $0.int(0) }
}
```

## The API

- `Database` is `Sendable`: one connection behind the database's own lock,
  so every caller gets it to itself, one after another, and what a closure
  runs (a transaction, a prepared statement's rows) runs with nothing from
  another caller between. The lock is recursive: the database called from
  inside one of its own closures runs there.
- The methods run on the caller's thread: SQLite's calls are quick, and the
  main actor may make them. `perform { connection in … }` runs a closure off
  the caller's executor instead, for work that should not hold the caller's
  thread; cancelling its task stops the statement under way (SQLite checks
  every thousand steps) with an error whose `isInterrupted` is true. (One
  async entry point rather than an `async` twin of each method: Swift prefers
  an `async` overload inside an `async` function, so twins would make every
  synchronous call there need an `await`.)
- `execute(_:)` runs SQL with no arguments, one statement or several.
  `run(_:_:)` runs one statement with arguments and returns how many rows it
  changed. `query(_:_:row:)` reads each row with your closure.
  `prepare(_:_:)` hands you a `Statement` to run many times.
  `transaction(_:_:)` commits when its closure returns and rolls back when it
  throws; inside another transaction it is a savepoint.
- Arguments are `SQLiteBindable`: `Int` and the other integer types,
  `Double`, `Float`, `String`, `Bool` (1 or 0), `[UInt8]` (a blob),
  `SQLiteValue`, and optionals of them (NULL). Parameters are `?` (in order)
  or named (`:name`, bound with `bind(_:named:)`).
- A `Row` reads its columns by index as typed values, following SQLite's
  conversions (`int`, `int64`, `double`, `bool`, `text`, `blob`, `isNull`),
  or as an `SQLiteValue` by index (`value(_:)`) or by name (`row["body"]`).
- `Connection`, `Statement` and `Row` belong to the closure that hands them
  out: they are not `Sendable`, and one used after its closure returns stops
  the program rather than race the thread that has the connection now.
- `SQLiteError` carries SQLite's extended result code, its message and the
  SQL. `isBusy`, `isConstraint` and `isInterrupted` cover the usual
  questions.
- `serialize()` and `Database(serialized:)` copy a database to bytes and back.
- For what this does not wrap, `Connection.withUnsafeHandle` gives you the
  `sqlite3` pointer (`import CSQLite`).

## WebAssembly (WASI)

On WASI SQLite is built without dlopen, a write-ahead log or mmap, with the
"unix-none" VFS: no lock files, which a host that keeps an app's files past
its process (a browser, in IndexedDB) would otherwise keep when the process
ended inside a transaction. It is thread-safe in a module built for
`wasm32-wasip1-threads` and single-threaded otherwise.

## Using it

SwiftPM:

```swift
.package(url: "https://github.com/AttilaTheFun/swift_sqlite.git", from: "0.34.0"),
// …
.product(name: "SwiftSQLite", package: "swift_sqlite"),
```

Bazel (`MODULE.bazel`):

```starlark
bazel_dep(name = "swift_sqlite", version = "0.34")
git_override(
    module_name = "swift_sqlite",
    remote = "https://github.com/AttilaTheFun/swift_sqlite.git",
    tag = "v0.34",
)
```

then `@swift_sqlite//:SwiftSQLite` (or `@swift_sqlite//:CSQLite` for the C
API alone).

## License

Apache 2.0 (LICENSE). SQLite itself is in the public domain
(https://sqlite.org/copyright.html).
