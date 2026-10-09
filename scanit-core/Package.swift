// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "scanit-core",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ScanItCore", targets: ["ScanItCore"]),
    ],
    targets: [
        .target(name: "ScanItCore"),
        .testTarget(name: "ScanItCoreTests", dependencies: ["ScanItCore"]),
    ]
)
