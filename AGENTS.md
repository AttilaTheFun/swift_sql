# AGENTS.md — swift_sql

SQLite for Swift: `CSwiftSQL` (the C API: the system's SQLite on Apple's
platforms, the vendored amalgamation elsewhere) and `SwiftSQL` (a thin,
strict-concurrency-safe Swift layer over it). Public. Part of a set of
packages and apps released together since 0.34: Visor among them reaches
SQLite through it. Tagged with the stack's number at its releases
(v0.34, …; tags `v0.N.0` from 0.35, which SwiftPM reads as versions).

- **A Swift package only** (no Bazel module; Bazel
  consumers take it through rules_swift_package_manager, as
  `@swiftpkg_swift_sql//:SwiftSQL`). SQLite's compile options live in
  `Sources/CSwiftSQL/cswiftsql.c`, not in the manifest, so every build of the
  package builds the same SQLite. Change them there.
- **Upgrading SQLite**: replace `Sources/CSwiftSQL/amalgamation/sqlite3.h` and
  `sqlite3.c.h` (the amalgamation's sqlite3.c, renamed: a header is never
  compiled on its own, and rules_swift_package_manager keeps headers where it
  drops a manifest's excluded sources) with a new amalgamation from sqlite.org (check its sha256 against the one
  sqlite.org publishes), update the version in README.md, run both test
  suites.
- **WASI**: cswiftsql.c picks thread safety from `__wasm_atomics__` (Clang
  defines it for `wasm32-wasip1-threads`, not for `wasm32-wasip1`). Clang's
  own headers come from the toolchain: under Bazel, rules_swift's WebAssembly
  C toolchain needs the Swift SDK's clang resource directory for compiles
  (Isomer's patch), or Bazel rejects `<stdarg.h>` by absolute path. Nothing
  WASI-specific belongs in the manifest (a remote package's unsafeFlags are
  refused by SwiftPM). WebAssembly builds are tested where they run (Isomer's
  WAMR and WasmKit hosts), not here.
- **The Swift layer stays thin**: no ORM, no query builder, no Foundation.
  New API wraps a C call or two and keeps `Database` `Sendable` with
  `Connection`/`Statement`/`Row` confined to their closures.
- Tests: `swift test` (macOS), and `swift test` in a Linux container (CI's `swift:6.2-noble`; in an image
  whose `clang` is not the Swift toolchain's, set `CC` to the toolchain's).

## The repository's icon

`.github/SwiftSQL.icon` (Icon Composer) and its rendering, `.github/icon.png`,
where Reviews and other tools look for a repository's icon. Rendered with
`ictool` (in Xcode's Icon Composer.app, Contents/Executables):

    ictool .github/SwiftSQL.icon --export-image --output-file .github/icon.png \
        --platform iOS --rendition Default --width 512 --height 512 --scale 1

No README in .github: GitHub would show it as the repository's.
