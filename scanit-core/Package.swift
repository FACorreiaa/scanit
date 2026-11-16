// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "scanit-core",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ScanItCore", targets: ["ScanItCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "ScanItCore",
            dependencies: [.product(name: "Algorithms", package: "swift-algorithms")],
            // Shared with Android, which reads the same file (BACKLOG CMP-001).
            resources: [.copy("Resources/chains.json")]
        ),
        .testTarget(name: "ScanItCoreTests", dependencies: ["ScanItCore"]),
    ]
)
