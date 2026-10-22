import Foundation

/// Recorded shelf labels: what Vision read on each photo, and the price the owner wants prefilled.
/// `tools/label-bench --record` writes it to `scanit-core/Fixtures/labels.json`; the photos stay
/// local. Replaying it through `PriceParser` is the regression gate that runs on Linux CI.
public struct LabelSet: Codable, Sendable {
    public struct Label: Codable, Sendable {
        public struct Text: Codable, Sendable {
            public let text: String
            public let box: LabelBox
        }

        public let name: String
        public let currency: String
        /// `nil` when the right answer is "ask the user", e.g. only a per-kg price is shown.
        public let expectedMinor: Int?
        public let barcode: LabelBox?
        public let texts: [Text]

        public init(name: String, currency: String, expectedMinor: Int?, barcode: LabelBox?, texts: [RecognizedText]) {
            self.name = name
            self.currency = currency
            self.expectedMinor = expectedMinor
            self.barcode = barcode?.rounded()
            self.texts = texts.compactMap { item in item.box.map { Text(text: item.text, box: $0.rounded()) } }
        }

        public var recognized: [RecognizedText] {
            texts.map { RecognizedText(text: $0.text, box: $0.box) }
        }
    }

    /// Lowest accepted share of correct top candidates, 0…1. Raised by hand as the parser improves.
    public var floor: Double
    public var labels: [Label]

    public init(floor: Double, labels: [Label]) {
        self.floor = floor
        self.labels = labels
    }
}

private extension LabelBox {
    /// Four decimals is well under a pixel and keeps the recorded fixture readable in diffs.
    func rounded() -> LabelBox {
        func round4(_ value: Double) -> Double { (value * 10_000).rounded() / 10_000 }
        return LabelBox(x: round4(x), y: round4(y), width: round4(width), height: round4(height))
    }
}

public struct LabelScore: Sendable {
    public struct Row: Sendable {
        public let name: String
        public let expectedMinor: Int?
        public let gotMinor: Int?
        public let confidence: Double?
        public var isHit: Bool { expectedMinor == gotMinor }
    }

    public let rows: [Row]
    public var hits: Int { rows.count(where: \.isHit) }
    public var rate: Double { rows.isEmpty ? 0 : Double(hits) / Double(rows.count) }
}

extension LabelSet {
    /// Scores the parser's top candidate against each label's expected price.
    public func score() -> LabelScore {
        LabelScore(rows: labels.map { label in
            let best = PriceParser(currency: label.currency).parse(label.recognized).best
            return LabelScore.Row(
                name: label.name, expectedMinor: label.expectedMinor,
                gotMinor: best?.total.amountMinor, confidence: best?.confidence
            )
        })
    }
}
