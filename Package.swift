// swift-tools-version: 6.0
import PackageDescription

/// Apple's platforms link the system's SQLite; the rest build the copy here.
let apple: [Platform] = [.macOS, .macCatalyst, .iOS, .tvOS, .watchOS, .visionOS]

let package = Package(
    name: "swift_sqlite",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [
        .library(name: "SwiftSQLite", targets: ["SwiftSQLite"]),
        .library(name: "CSQLite", targets: ["CSQLite"]),
    ],
    targets: [
        .target(
            name: "CSQLite",
            // csqlite.c compiles the amalgamation (amalgamation/sqlite3.c.h,
            // SQLite's sqlite3.c under a header's name, so that it is never
            // compiled on its own and comes along wherever the target's
            // headers go) with its options, off Apple's platforms.
            linkerSettings: [
                .linkedLibrary("sqlite3", .when(platforms: apple)),
                .linkedLibrary("m", .when(platforms: [.linux, .android])),
                .linkedLibrary("pthread", .when(platforms: [.linux])),
            ]),
        .target(name: "SwiftSQLite", dependencies: ["CSQLite"]),
        .testTarget(name: "SwiftSQLiteTests", dependencies: ["SwiftSQLite"]),
    ],
    swiftLanguageModes: [.v6]
)
