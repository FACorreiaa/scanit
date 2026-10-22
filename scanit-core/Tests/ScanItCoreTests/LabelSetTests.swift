import Foundation
import Testing
@testable import ScanItCore

/// Replays the recorded real shelf labels (`Fixtures/labels.json`, written by
/// `tools/label-bench --record`) through the parser. Fails when accuracy drops below the floor.
@Suite("LabelSet")
struct LabelSetTests {
    @Test func accuracyStaysAboveFloor() throws {
        let set = try Fixtures.decode(LabelSet.self, from: "labels.json")
        let score = set.score()
        let misses = score.rows.filter { !$0.isHit }.map(\.name)
        #expect(score.rate >= set.floor, "\(score.hits) of \(score.rows.count) prefilled correctly; misses: \(misses)")
    }

    @Test func recordedLabelRoundTrips() throws {
        let label = LabelSet.Label(
            name: "IMG_0001.jpg", currency: "EUR", expectedMinor: 249,
            barcode: LabelBox(x: 0.1, y: 0.7, width: 0.3, height: 0.1),
            texts: [
                RecognizedText(text: "2,49 €", box: LabelBox(x: 0.5, y: 0.3, width: 0.3, height: 0.2)),
                RecognizedText(text: "no box", height: 0.1),
            ]
        )
        let decoded = try JSONDecoder().decode(
            LabelSet.self, from: JSONEncoder().encode(LabelSet(floor: 1, labels: [label]))
        )
        #expect(decoded.labels.first?.texts.count == 1)
        #expect(decoded.score().hits == 1)
    }
}
