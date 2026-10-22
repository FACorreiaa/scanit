import Testing
@testable import ScanItCore

struct PriceVector: Decodable, Sendable, CustomTestStringConvertible {
    struct Item: Decodable, Sendable {
        let text: String
        let height: Double?
        let box: LabelBox?

        var recognized: RecognizedText {
            box.map { RecognizedText(text: text, box: $0) } ?? RecognizedText(text: text, height: height ?? 0)
        }
    }

    struct Expected: Decodable, Sendable {
        let totalMinor: Int
        let quantity: Int
        let candidates: Int?
        /// When present: whether the best price is confident enough to be filled in.
        let prefill: Bool?
    }

    let name: String
    let currency: String
    let items: [Item]
    let barcode: LabelBox?
    let expected: Expected?
    /// When present: how many flagged multi-buy candidates the label yields.
    let multiBuys: Int?

    var testDescription: String { name }
}

private let priceVectors = (try? Fixtures.decode([PriceVector].self, from: "prices.json")) ?? []

@Suite("PriceParser")
struct PriceParserTests {
    @Test func fixturesLoad() {
        #expect(priceVectors.count >= 27)
    }

    @Test(arguments: priceVectors)
    func vector(_ vector: PriceVector) throws {
        let parser = PriceParser(currency: vector.currency)
        let result = parser.parse(vector.items.map(\.recognized), barcode: vector.barcode)
        if let multiBuys = vector.multiBuys {
            #expect(result.candidates.count(where: \.isMultiBuy) == multiBuys)
        }

        guard let expected = vector.expected else {
            #expect(result.best == nil)
            #expect(result.prefill == nil)
            return
        }
        let best = try #require(result.best)
        #expect(best.total == Money(amountMinor: expected.totalMinor, currency: vector.currency))
        #expect(best.quantity == expected.quantity)
        if let count = expected.candidates {
            #expect(result.candidates.filter { !$0.isUnitPrice && !$0.isMultiBuy }.count == count)
        }
        if let prefill = expected.prefill {
            #expect((result.prefill != nil) == prefill)
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
