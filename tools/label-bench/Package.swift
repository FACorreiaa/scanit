// swift-tools-version: 6.0

import PackageDescription

/// IOS-006 spike harness: Vision text recognition + ScanItCore's PriceParser over shelf-label photos.
let package = Package(
    name: "label-bench",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "label-bench", targets: ["LabelBench"])],
    dependencies: [.package(path: "../../scanit-core")],
    targets: [
        .executableTarget(
            name: "LabelBench",
            dependencies: [.product(name: "ScanItCore", package: "scanit-core")]
        ),
    ]
)
