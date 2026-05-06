// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CodexMonitor",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0")
    ],
    targets: [
        .executableTarget(
            name: "CodexMonitor",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "CodexMonitor",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "CodexMonitorTests",
            dependencies: ["CodexMonitor"],
            path: "Tests/CodexMonitorTests",
            // Bundle JSON fixtures as resources so XCTest can locate them
            // via Bundle.module regardless of working directory. Keep the
            // _comment-key fixtures human-editable — no preprocessing.
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
