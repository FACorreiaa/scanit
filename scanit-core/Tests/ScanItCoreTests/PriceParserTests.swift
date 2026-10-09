import Testing
@testable import ScanItCore

struct PriceVector: Decodable, Sendable, CustomTestStringConvertible {
    struct Item: Decodable, Sendable {
        let text: String
        let height: Double
    }

    struct Expected: Decodable, Sendable {
        let totalMinor: Int
        let quantity: Int
        let candidates: Int?
    }

    let name: String
    let currency: String
    let items: [Item]
    let expected: Expected?

    var testDescription: String { name }
}

private let priceVectors = (try? Fixtures.decode([PriceVector].self, from: "prices.json")) ?? []

@Suite("PriceParser")
struct PriceParserTests {
    @Test func fixturesLoad() {
        #expect(priceVectors.count >= 19)
    }

    @Test(arguments: priceVectors)
    func vector(_ vector: PriceVector) throws {
        let parser = PriceParser(currency: vector.currency)
        let result = parser.parse(vector.items.map { RecognizedText(text: $0.text, height: $0.height) })

        guard let expected = vector.expected else {
            #expect(result.best == nil)
            return
        }
        let best = try #require(result.best)
        #expect(best.total == Money(amountMinor: expected.totalMinor, currency: vector.currency))
        #expect(best.quantity == expected.quantity)
        if let count = expected.candidates {
            #expect(result.candidates.filter { !$0.isUnitPrice }.count == count)
        }
    }

    @Test func confidenceIsBounded() throws {
        let parser = PriceParser(currency: "EUR")
        let single = parser.parse([RecognizedText(text: "1,99 €", height: 0.1)])
        let close = parser.parse([
            RecognizedText(text: "1,99", height: 0.10),
            RecognizedText(text: "2,49", height: 0.098),
        ])
        let singleConfidence = try #require(single.best?.confidence)
        let closeConfidence = try #require(close.best?.confidence)
        #expect((0...1).contains(singleConfidence))
        #expect((0...1).contains(closeConfidence))
        #expect(singleConfidence > closeConfidence)
    }
}
