import Foundation

/// Loads the shared JSON vectors from `scanit-core/Fixtures/`.
///
/// They live outside the test target on purpose: the Android port runs the same files,
/// so they cannot be SwiftPM resources.
enum Fixtures {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent() // ScanItCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // scanit-core
        .appending(path: "Fixtures")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: name))
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}
