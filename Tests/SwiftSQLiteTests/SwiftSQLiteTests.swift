import SwiftSQLite
import XCTest

final class SwiftSQLiteTests: XCTestCase {
    private func makeDatabase() throws -> Database {
        let database = try Database.inMemory()
        try database.execute("""
            CREATE TABLE items(id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, score REAL, data BLOB, flag INTEGER);
            """)
        return database
    }

    func testValuesRoundTrip() throws {
        let database = try makeDatabase()
        let bytes: [UInt8] = [0, 1, 2, 255]
        let changed = try database.run(
            "INSERT INTO items(name, score, data, flag) VALUES (?, ?, ?, ?)", "alpha", 2.5, bytes, true)
        XCTAssertEqual(changed, 1)
        try database.run("INSERT INTO items(name, score, data, flag) VALUES (?, ?, ?, ?)",
                         "beta", Optional<Double>.none, [UInt8](), false)
        let rows = try database.query("SELECT id, name, score, data, flag FROM items ORDER BY id") { row in
            (row.int(0), row.text(1), row.isNull(2) ? nil : row.double(2), row.blob(3), row.bool(4))
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].1, "alpha")
        XCTAssertEqual(rows[0].2, 2.5)
        XCTAssertEqual(rows[0].3, bytes)
        XCTAssertEqual(rows[0].4, true)
        XCTAssertNil(rows[1].2)
        XCTAssertEqual(rows[1].3, [], "a zero-length blob is a blob, not NULL")
        XCTAssertEqual(rows[1].4, false)
    }

    func testRowByNameAndValue() throws {
        let database = try makeDatabase()
        try database.run("INSERT INTO items(name, score) VALUES (?, ?)", "gamma", 1)
        let values = try database.query("SELECT name, score, data FROM items") { row in
            (row["name"], row["score"], row["data"], row["missing"], row.columnNames)
        }
        XCTAssertEqual(values.first?.0, .text("gamma"))
        XCTAssertEqual(values.first?.1, .real(1), "REAL affinity stores 1 as 1.0")
        XCTAssertEqual(values.first?.2, .null)
        XCTAssertNil(values.first?.3)
        XCTAssertEqual(values.first?.4, ["name", "score", "data"])
    }

    func testUnicodeText() throws {
        let database = try makeDatabase()
        let name = "Studio’s Mac — 日本語 🚀"
        try database.run("INSERT INTO items(name) VALUES (?)", name)
        XCTAssertEqual(try database.query("SELECT name FROM items") { $0.text(0) }, [name])
    }

    func testPreparedStatementReused() throws {
        let database = try makeDatabase()
        let inserted = try database.prepare("INSERT INTO items(name, score) VALUES (?, ?)") { statement in
            for index in 0..<100 {
                try statement.bind("item \(index)", Double(index))
                try statement.run()
            }
            return statement.parameterCount
        }
        XCTAssertEqual(inserted, 2)
        XCTAssertEqual(try database.query("SELECT count(*), sum(score) FROM items") { [$0.int(0), $0.int(1)] }, [[100, 4950]])
    }

    func testNamedParameters() throws {
        let database = try makeDatabase()
        try database.prepare("INSERT INTO items(name, score) VALUES (:name, :score)") { statement in
            try statement.bind("named", named: ":name")
            try statement.bind(7.0, named: ":score")
            try statement.run()
            XCTAssertThrowsError(try statement.bind(1, named: ":nope"))
        }
        XCTAssertEqual(try database.query("SELECT score FROM items WHERE name = ?", "named") { $0.double(0) }, [7])
    }

    func testWrongArgumentCountThrows() throws {
        let database = try makeDatabase()
        XCTAssertThrowsError(try database.run("INSERT INTO items(name) VALUES (?)", "a", "b"))
    }

    func testErrorsCarryCodeMessageAndSQL() throws {
        let database = try makeDatabase()
        try database.run("INSERT INTO items(name) VALUES (?)", "same")
        do {
            try database.run("INSERT INTO items(name) VALUES (?)", "same")
            XCTFail("a duplicate should fail")
        } catch let error as SQLiteError {
            XCTAssertTrue(error.isConstraint)
            XCTAssertEqual(error.extendedCode, 2067, "SQLITE_CONSTRAINT_UNIQUE")
            XCTAssertTrue(error.message.contains("UNIQUE"), error.message)
            XCTAssertEqual(error.sql, "INSERT INTO items(name) VALUES (?)")
        }
        XCTAssertThrowsError(try database.execute("NOT SQL")) { error in
            XCTAssertEqual((error as? SQLiteError)?.code, 1, "SQLITE_ERROR")
        }
    }

    func testTransactionCommitsAndRollsBack() throws {
        let database = try makeDatabase()
        let id = try database.transaction { connection in
            try connection.run("INSERT INTO items(name) VALUES (?)", "kept")
            return connection.lastInsertRowID
        }
        XCTAssertEqual(id, 1)
        struct Stop: Error {}
        XCTAssertThrowsError(try database.transaction(.immediate) { connection in
            try connection.run("INSERT INTO items(name) VALUES (?)", "dropped")
            throw Stop()
        })
        XCTAssertEqual(try database.query("SELECT name FROM items") { $0.text(0) }, ["kept"])
    }

    func testNestedTransactionIsASavepoint() throws {
        let database = try makeDatabase()
        struct Stop: Error {}
        try database.transaction { outer in
            try outer.run("INSERT INTO items(name) VALUES (?)", "outer")
            XCTAssertThrowsError(try outer.transaction { inner in
                try inner.run("INSERT INTO items(name) VALUES (?)", "inner")
                throw Stop()
            })
            try outer.transaction { inner in
                try inner.run("INSERT INTO items(name) VALUES (?)", "inner kept")
            }
            XCTAssertTrue(outer.isInTransaction)
        }
        XCTAssertEqual(try database.query("SELECT name FROM items ORDER BY id") { $0.text(0) }, ["outer", "inner kept"])
    }

    func testDatabaseUsedInsideItsOwnClosure() throws {
        // The lock is recursive: the database called from inside one of its
        // closures runs there, in the same transaction.
        let database = try makeDatabase()
        try database.transaction { _ in
            try database.run("INSERT INTO items(name) VALUES (?)", "reentered")
        }
        XCTAssertEqual(try database.query("SELECT count(*) FROM items") { $0.int(0) }, [1])
    }

    func testFullTextSearch() throws {
        let database = try Database.inMemory()
        try database.execute("CREATE VIRTUAL TABLE notes USING fts5(body)")
        for body in ["the quick brown fox", "a lazy dog", "brown bread"] {
            try database.run("INSERT INTO notes(body) VALUES (?)", body)
        }
        XCTAssertEqual(try database.query("SELECT count(*) FROM notes WHERE notes MATCH ?", "brown") { $0.int(0) }, [2])
    }

    func testSerializeAndRestore() throws {
        let database = try makeDatabase()
        for index in 0..<50 { try database.run("INSERT INTO items(name) VALUES (?)", "row \(index)") }
        let image = try database.serialize()
        XCTAssertGreaterThan(image.count, 0)
        let copy = try Database(serialized: image)
        XCTAssertEqual(try copy.query("SELECT count(*) FROM items") { $0.int(0) }, [50])
        try copy.run("INSERT INTO items(name) VALUES (?)", "grown")
        XCTAssertEqual(try copy.query("SELECT count(*) FROM items") { $0.int(0) }, [51])
    }

    func testFileDatabasePersistsAndClosedThrows() throws {
        let directory = NSTemporaryDirectory() + "swift_sqlite_\(UInt32.random(in: 0...UInt32.max))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let path = directory + "/test.sqlite"
        do {
            let database = try Database(path: path)
            try database.execute("CREATE TABLE kept(value TEXT)")
            try database.run("INSERT INTO kept VALUES (?)", "on disk")
            database.close()
            database.close()
            XCTAssertThrowsError(try database.execute("SELECT 1")) { error in
                XCTAssertEqual((error as? SQLiteError)?.code, 21, "SQLITE_MISUSE")
                XCTAssertEqual((error as? SQLiteError)?.isClosed, true)
            }
        }
        let reopened = try Database(path: path, options: .readOnly)
        XCTAssertEqual(try reopened.query("SELECT value FROM kept") { $0.text(0) }, ["on disk"])
        XCTAssertThrowsError(try reopened.run("INSERT INTO kept VALUES (?)", "no")) { error in
            XCTAssertEqual((error as? SQLiteError)?.code, 8, "SQLITE_READONLY")
        }
        XCTAssertThrowsError(try Database(path: directory + "/missing/none.sqlite"))
    }

    func testAsyncCallsFromManyTasks() async throws {
        let database = try makeDatabase()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<200 {
                group.addTask {
                    _ = try await database.perform { connection in
                        try connection.run("INSERT INTO items(name, score) VALUES (?, ?)", "task \(index)", Double(index))
                    }
                }
            }
            try await group.waitForAll()
        }
        let total = try await database.perform { try $0.query("SELECT count(*), sum(score) FROM items") { row in [row.int(0), row.int(1)] } }
        XCTAssertEqual(total, [[200, 19900]])
        let names = try await database.perform { connection in
            try connection.transaction { connection in
                try connection.query("SELECT name FROM items WHERE score < 3 ORDER BY score") { $0.text(0) ?? "" }
            }
        }
        // The synchronous methods need no `await` in an async function.
        XCTAssertEqual(try database.query("SELECT count(*) FROM items") { $0.int(0) }, [200])
        XCTAssertEqual(names, ["task 0", "task 1", "task 2"])
    }

    func testCancellationInterrupts() async throws {
        let database = try Database.inMemory()
        let task = Task {
            // Counts for a long while unless interrupted.
            try await database.perform { connection in
                try connection.query("""
                    WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1000000000)
                    SELECT count(*) FROM n
                    """) { $0.int(0) }
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("the query should have been interrupted")
        } catch let error as SQLiteError {
            XCTAssertTrue(error.isInterrupted, "\(error)")
        }
        XCTAssertEqual(try database.query("SELECT 1") { $0.int(0) }, [1], "the database works after an interrupt")
        // A task cancelled before its call has the connection runs nothing.
        let cancelled = Task {
            try await Task.sleep(nanoseconds: 20_000_000)
            return try await database.perform { try $0.run("CREATE TABLE never(x)") }
        }
        cancelled.cancel()
        _ = try? await cancelled.value
        XCTAssertEqual(try database.query("SELECT count(*) FROM sqlite_master WHERE name = 'never'") { $0.int(0) }, [0])
    }
}
