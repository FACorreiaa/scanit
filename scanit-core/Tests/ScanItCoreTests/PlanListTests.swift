import Foundation
import Testing
@testable import ScanItCore

/// `Fixtures/plan-list.json`: hand-computed expectations, shared with Android.
private struct PlanListFixture: Decodable {
    struct Line: Decodable {
        let key, text: String
        let packs: Int
        let meals: [String]
        let inPantry: Bool
    }
    struct Case: Decodable { let name: String; let meals: [PlannedIngredients]; let expected: [Line] }

    let cases: [Case]
}

@Suite("Plan to list (MEAL-003)")
struct PlanListTests {
    @Test func fixtureCases() throws {
        let fixture = try WireCoding.decoder().decode(PlanListFixture.self, from: Fixtures.data("plan-list.json"))
        for item in fixture.cases {
            let lines = PlanList.lines(item.meals)
            #expect(lines.map(\.key) == item.expected.map(\.key), "\(item.name)")
            for (line, want) in zip(lines, item.expected) {
                #expect(line.text == want.text, "\(item.name) \(want.key)")
                #expect(line.packs == want.packs, "\(item.name) \(want.key)")
                #expect(line.meals == want.meals, "\(item.name) \(want.key)")
                #expect(line.inPantry == want.inPantry, "\(item.name) \(want.key)")
            }
        }
    }

    @Test func keysIgnoreCaseAccentsAndSpacing() {
        #expect(PlanList.key(text: "  Pão  de Forma ", code: nil) == PlanList.key(text: "pao de forma", code: nil))
        #expect(PlanList.key(text: "Leite", code: "05601234567892") == "code:05601234567892")
        #expect(PlanList.key(text: "Leite", code: "") == "text:leite", "an empty code is no code")
    }
}
