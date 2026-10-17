# AGENTS.md — swift_sqlite

SQLite for Swift: `CSQLite` (the C API: the system's SQLite on Apple's
platforms, the vendored amalgamation elsewhere) and `SwiftSQLite` (a thin,
strict-concurrency-safe Swift layer over it). Public. Part of Logan's stack
since 0.34: Visor (red and blue), Isomer's examples and swift_proto_sql
reach SQLite through it. Tagged with the stack's number at its releases
(v0.34, …).

- **One build, two build systems.** SQLite's compile options live in
  `Sources/CSQLite/csqlite.c`, not in a build file, so Bazel (BUILD.bazel)
  and SwiftPM (Package.swift) build the same SQLite. Change them there.
- **Upgrading SQLite**: replace `Sources/CSQLite/amalgamation/sqlite3.{c,h}`
  with a new amalgamation from sqlite.org (check its sha256 against the one
  sqlite.org publishes), update the version in README.md, run both test
  suites.
- **WASI**: csqlite.c picks thread safety from `__wasm_atomics__` (Clang
  defines it for `wasm32-wasip1-threads`, not for `wasm32-wasip1`); the two
  headers in `Sources/CSQLite/wasi` and `-nobuiltininc` are for rules_swift's
  WebAssembly C toolchain, which does not list Clang's resource directory.
  WebAssembly builds are tested where they run (Isomer's WAMR and WasmKit
  hosts), not here.
- **The Swift layer stays thin**: no ORM, no query builder, no Foundation.
  New API wraps a C call or two and keeps `Database` `Sendable` with
  `Connection`/`Statement`/`Row` confined to their closures.
- Tests: `swift test` and `bazel test //:SwiftSQLiteTests` (macOS), and
  `swift test` in a Linux container (CI's `swift:6.2-noble`; in an image
  whose `clang` is not the Swift toolchain's, set `CC` to the toolchain's).
