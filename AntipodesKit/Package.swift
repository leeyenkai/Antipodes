// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AntipodesKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "AntipodesKit", targets: ["AntipodesUI"]),
        .library(name: "AntipodesCore", targets: ["AntipodesCore"]),
        .library(name: "AntipodesPlaces", targets: ["AntipodesPlaces"]),
        .library(name: "AntipodesStats", targets: ["AntipodesStats"]),
        .library(name: "AntipodesExport", targets: ["AntipodesExport"]),
        .library(name: "AntipodesStore", targets: ["AntipodesStore"]),
        .library(name: "AntipodesGlobe", targets: ["AntipodesGlobe"]),
        .library(name: "AntipodesImport", targets: ["AntipodesImport"]),
    ],
    targets: [
        // Value types and maths. Depends on nothing but the standard library.
        .target(name: "AntipodesCore"),

        // Read-only place database. Links the system SQLite; no third-party code.
        .target(
            name: "AntipodesPlaces",
            dependencies: ["AntipodesCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),

        // Pure statistics over AntipodesCore value types. Must not import SwiftData.
        .target(name: "AntipodesStats", dependencies: ["AntipodesCore"]),

        // CSV and JSON export of the user's whole log.
        .target(name: "AntipodesExport", dependencies: ["AntipodesCore"]),

        // SwiftData models and CloudKit mirroring. The only module that imports SwiftData.
        .target(name: "AntipodesStore", dependencies: ["AntipodesCore"]),

        // Globe geometry: orthographic projection, limb clipping, the bundled border
        // file and the replay timeline. Pure, and must not import SwiftUI or MapKit.
        .target(name: "AntipodesGlobe", dependencies: ["AntipodesCore"]),
        // Reading other apps' files and clustering photo locations into suggested
        // visits. Pure: matching against the place database is passed in as a closure.
        .target(name: "AntipodesImport", dependencies: ["AntipodesCore"]),

        // SwiftUI screens.
        .target(
            name: "AntipodesUI",
            dependencies: [
                "AntipodesCore",
                "AntipodesPlaces",
                "AntipodesStats",
                "AntipodesExport",
                "AntipodesStore",
                "AntipodesGlobe",
                "AntipodesImport",
            ]
        ),

        .testTarget(name: "AntipodesCoreTests", dependencies: ["AntipodesCore"]),
        .testTarget(
            name: "AntipodesPlacesTests",
            dependencies: ["AntipodesPlaces", "AntipodesCore"]
        ),
        .testTarget(
            name: "AntipodesStatsTests",
            dependencies: ["AntipodesStats", "AntipodesCore"]
        ),
        .testTarget(
            name: "AntipodesExportTests",
            dependencies: ["AntipodesExport", "AntipodesCore"]
        ),
        .testTarget(
            name: "AntipodesGlobeTests",
            dependencies: ["AntipodesGlobe", "AntipodesCore"]
        ),
        .testTarget(
            name: "AntipodesImportTests",
            dependencies: ["AntipodesImport", "AntipodesCore"]
        ),
    ]
)
