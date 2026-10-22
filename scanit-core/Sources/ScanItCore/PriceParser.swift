import Algorithms
import Foundation

/// A rectangle in one frame, normalised to 0…1 with the origin at the top left (y grows down).
/// Text and barcode boxes from the same still share this space, so the parser can compare them.
public struct LabelBox: Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
}

/// One piece of text the scanner recognised on a shelf label.
public struct RecognizedText: Hashable, Sendable {
    public let text: String
    /// Bounding-box height, in any unit as long as it is the same for every item in one frame.
    /// The shelf price is the biggest number on the label, so height is the main ranking signal.
    public let height: Double
    /// Where the text sits in the frame, when the recogniser reports it (`LabelReader` does).
    public let box: LabelBox?

    public init(text: String, height: Double) {
        self.text = text
        self.height = height
        self.box = nil
    }

    public init(text: String, box: LabelBox) {
        self.text = text
        self.height = box.height
        self.box = box
    }
}

public struct PriceCandidate: Hashable, Sendable {
    /// What the user pays for `quantity` units: `2 x 0,99` is 1,98 for 2; `3 for 5.00` is 5.00 for 3.
    public let total: Money
    public let quantity: Int
    /// A per-kg / per-litre / per-100 g price. Kept so the UI can show it, never picked as best.
    public let isUnitPrice: Bool
    /// `2 x 0,99` or `3 for 5.00`. Shown as a flag, never picked as best: what one item costs is a guess.
    public let isMultiBuy: Bool
    public let hasCurrencySymbol: Bool
    public let sourceText: String
    public let height: Double
    /// Where the text was, for drawing candidate boxes. `nil` when the recogniser gave no box.
    public let box: LabelBox?
    /// 0…1. Low when another price on the label is almost as big. The user always confirms.
    public let confidence: Double
}

public struct PriceParseResult: Sendable {
    /// Item prices first (best first), then multi-buys, then unit prices.
    public let candidates: [PriceCandidate]

    public var best: PriceCandidate? {
        candidates.first { !$0.isUnitPrice && !$0.isMultiBuy }
    }

    /// The price to fill in for the user, or `nil` when the label is too ambiguous to guess.
    public var prefill: PriceCandidate? {
        best.flatMap { $0.confidence >= PriceParser.prefillThreshold ? $0 : nil }
    }
}

/// Finds the shelf price among recognised text. Pure and deterministic; vectors in
/// `scanit-core/Fixtures/prices.json` are shared with Android.
public struct PriceParser: Sendable {
    public let currency: String
    private let minorDigits: Int

    public init(currency: String) {
        self.currency = currency.uppercased()
        self.minorDigits = Money.minorUnitDigits(for: currency)
    }

    /// Below this confidence nothing is prefilled and the candidates are offered as chips.
    /// A wrong price accepted without noticing is worse than typing it. Tuned on `tools/label-bench`.
    public static let prefillThreshold = 0.6

    /// `barcode` is the locked product's barcode box in the same frame: a price near it (and
    /// below it) belongs to this product rather than to the neighbouring label.
    public func parse(_ items: [RecognizedText], barcode: LabelBox? = nil) -> PriceParseResult {
        let found = mergingSuperscriptCents(items).flatMap(amounts(in:))
        let (shelfPrices, unitPrices) = found.partitioned(by: \.isUnitPrice)
        let (itemPrices, multiBuys) = shelfPrices.partitioned(by: \.isMultiBuy)
        let tallest = shelfPrices.map(\.height).max() ?? 0
        let prices = rank(itemPrices, tallest: tallest, barcode: barcode)

        let confidence = bestConfidence(prices, multiBuys: multiBuys)
        let items: [PriceCandidate] = prices.enumerated().map { index, scored in
            scored.amount.candidate(currency: currency, confidence: index == 0 ? confidence : 0)
        }
        let deals: [PriceCandidate] = rank(multiBuys, tallest: tallest, barcode: barcode).map {
            $0.amount.candidate(currency: currency, confidence: 0)
        }
        let units: [PriceCandidate] = unitPrices.map { $0.candidate(currency: currency, confidence: 0) }
        return PriceParseResult(candidates: items + deals + units)
    }

    private struct ScoredAmount {
        var amount: FoundAmount
        var score: Double
    }

    /// Glyph height leads (the shelf price is the biggest number on the label). Nearness to the
    /// barcode settles labels that sit side by side; a currency symbol only breaks ties.
    private func rank(_ amounts: [FoundAmount], tallest: Double, barcode: LabelBox?) -> [ScoredAmount] {
        let scored = amounts.map { ScoredAmount(amount: $0, score: score($0, tallest: tallest, barcode: barcode)) }
        return scored.indices
            .sorted { lhs, rhs in
                scored[lhs].score != scored[rhs].score ? scored[lhs].score > scored[rhs].score : lhs < rhs
            }
            .map { scored[$0] }
    }

    private func score(_ amount: FoundAmount, tallest: Double, barcode: LabelBox?) -> Double {
        var score = tallest > 0 ? amount.height / tallest : 0
        if amount.hasSymbol { score += 0.01 }
        guard let barcode, let box = amount.box else { return score }
        let dx = box.midX - barcode.midX
        let dy = box.midY - barcode.midY
        let distance = (dx * dx + dy * dy).squareRoot()
        score += 0.15 * max(0, 1 - distance / 0.5)
        if box.midY > barcode.midY { score += 0.05 }
        return score
    }

    private func bestConfidence(_ prices: [ScoredAmount], multiBuys: [FoundAmount]) -> Double {
        guard let best = prices.first else { return 0 }
        var confidence = best.amount.hasSymbol && best.amount.hasDecimals ? 0.95 : 0.85
        // The same amount printed twice (big, and again as "PVP 2,49 €") is not a rival.
        if let rival = prices.dropFirst().first(where: { $0.amount.amountMinor != best.amount.amountMinor }),
           best.score > 0 {
            let ratio = rival.score / best.score
            confidence *= min(1, max(0, 0.4 + (1 - ratio) * 2))
        }
        // A promotion printed bigger than the item price: the label is about the deal, so ask.
        if multiBuys.contains(where: { $0.height > best.amount.height }) {
            confidence = min(confidence, Self.prefillThreshold / 2)
        }
        return confidence
    }

    // MARK: - Superscript cents

    /// A big "2" with a small, top-aligned "49" just to its right reads as 2,49. Vision returns
    /// the two sizes as separate items; anything it joins into one line is left alone.
    private func mergingSuperscriptCents(_ items: [RecognizedText]) -> [RecognizedText] {
        guard minorDigits == 2 else { return items }
        let whole = #/^\s*([€$£])?\s*(\d{1,3})\s*([€$£])?\s*$/#
        let cents = #/^\s*(\d{2})\s*([€$£])?\s*$/#

        var removed = Set<Int>()
        var merged: [RecognizedText] = []
        for (index, item) in items.enumerated() where !removed.contains(index) {
            guard let box = item.box, let units = item.text.wholeMatch(of: whole) else { continue }
            let partner = items.indices.first { other in
                guard other != index, !removed.contains(other), let small = items[other].box,
                      items[other].text.wholeMatch(of: cents) != nil
                else { return false }
                let ratio = small.height / box.height
                let gap = small.x - box.maxX
                return (0.25...0.75).contains(ratio)
                    && gap >= -0.25 * box.width && gap <= box.height
                    && abs(small.y - box.y) <= 0.3 * box.height
            }
            guard let partner, let fraction = items[partner].text.wholeMatch(of: cents) else { continue }
            removed.formUnion([index, partner])
            let symbol = units.output.1 ?? units.output.3 ?? fraction.output.2 ?? ""
            let small = items[partner].box!
            merged.append(RecognizedText(
                text: "\(symbol)\(units.output.2),\(fraction.output.1)",
                box: LabelBox(
                    x: box.x, y: min(box.y, small.y),
                    width: max(box.maxX, small.maxX) - box.x, height: box.height
                )
            ))
        }
        return items.indices.filter { !removed.contains($0) }.map { items[$0] } + merged
    }

    // MARK: - Scanning one text item

    private struct FoundAmount {
        var amountMinor: Int
        var quantity: Int
        var isDeal: Bool
        var hasSymbol: Bool
        var hasDecimals: Bool
        var isUnitPrice: Bool
        var sourceText: String
        var height: Double
        var box: LabelBox?

        var isMultiBuy: Bool { quantity > 1 }

        func candidate(currency: String, confidence: Double) -> PriceCandidate {
            let unit = Money(amountMinor: amountMinor, currency: currency)
            return PriceCandidate(
                total: isDeal ? unit : unit.multiplied(by: quantity),
                quantity: quantity,
                isUnitPrice: isUnitPrice,
                isMultiBuy: isMultiBuy,
                hasCurrencySymbol: hasSymbol,
                sourceText: sourceText,
                height: height,
                box: box,
                confidence: confidence
            )
        }
    }

    private static let symbolsBefore: Set<Character> = ["€", "$", "£", "¥"]
    private static let symbolsAfter: Set<Character> = ["€", "$", "£", "¥", "円"]
    private static let dealWords: Set<String> = ["for", "por", "para", "pour", "für"]
    private static let multiplySigns: Set<Character> = ["x", "X", "×", "*"]

    private func amounts(in item: RecognizedText) -> [FoundAmount] {
        let chars = Array(item.text.replacingOccurrences(of: "\u{00A0}", with: " "))
        var results: [FoundAmount] = []
        var index = 0
        while index < chars.count {
            guard chars[index].isASCIIDigit else { index += 1; continue }
            var end = index
            while end < chars.count, chars[end].isASCIIDigit || chars[end] == "." || chars[end] == "," {
                end += 1
            }
            while end > index, !chars[end - 1].isASCIIDigit { end -= 1 }
            defer { index = end }

            let number = String(chars[index..<end])
            let before = skipSpaces(chars, from: index - 1, step: -1)
            let after = skipSpaces(chars, from: end, step: 1)
            let hasSymbol = (before.map { Self.symbolsBefore.contains(chars[$0]) } ?? false)
                || (after.map { Self.symbolsAfter.contains(chars[$0]) } ?? false)

            guard let parsed = parseNumber(number) else { continue }
            let (minor, hasDecimals) = parsed
            guard minor > 0, hasDecimals || hasSymbol else { continue }

            let head = String(chars[..<index])
            let tail = String(chars[end...])
            let (quantity, isDeal) = multiplier(chars, numberStart: index, symbolBefore: before)
            results.append(FoundAmount(
                amountMinor: minor,
                quantity: quantity,
                isDeal: isDeal,
                hasSymbol: hasSymbol,
                hasDecimals: hasDecimals,
                isUnitPrice: Self.isUnitPrice(head: head, tail: tail),
                sourceText: item.text,
                height: item.height,
                box: item.box
            ))
        }
        return results
    }

    /// `(amountMinor, hadDecimalPart)` or `nil` when the digits cannot be a price in this currency.
    func parseNumber(_ number: String) -> (Int, Bool)? {
        let separators = number.filter { $0 == "." || $0 == "," }
        var integerPart = number
        var fraction = ""

        if let lastSeparator = separators.last {
            let mixed = Set(separators).count > 1
            let fractionCandidate = String(number[number.index(after: number.lastIndex(of: lastSeparator)!)...])
            let isDecimal = minorDigits > 0
                && fractionCandidate.count == minorDigits
                && (mixed || separators.count == 1)
            if isDecimal {
                fraction = fractionCandidate
                integerPart = String(number[..<number.lastIndex(of: lastSeparator)!])
            }
            let thousands = integerPart.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "." || $0 == "," })
            if thousands.count > 1 {
                guard thousands.dropFirst().allSatisfy({ $0.count == 3 }), (1...3).contains(thousands[0].count) else {
                    return nil
                }
            }
            integerPart = thousands.joined()
        }

        guard !integerPart.isEmpty, integerPart.count <= 7, let whole = Int(integerPart) else { return nil }
        let scale = (0..<minorDigits).reduce(1) { value, _ in value * 10 }
        let minor = whole * scale + (Int(fraction) ?? 0)
        return (minor, !fraction.isEmpty)
    }

    /// `2 x 0,99` → (2, false). `3 for 5.00` → (3, true). Anything else → (1, false).
    private func multiplier(_ chars: [Character], numberStart: Int, symbolBefore: Int?) -> (Int, Bool) {
        var cursor = numberStart - 1
        if let symbolBefore, Self.symbolsBefore.contains(chars[symbolBefore]) { cursor = symbolBefore - 1 }
        guard let marker = skipSpaces(chars, from: cursor, step: -1) else { return (1, false) }

        var isDeal = false
        var countEnd: Int?
        if Self.multiplySigns.contains(chars[marker]) {
            countEnd = skipSpaces(chars, from: marker - 1, step: -1)
        } else if chars[marker].isLetter {
            var start = marker
            while start > 0, chars[start - 1].isLetter { start -= 1 }
            guard Self.dealWords.contains(String(chars[start...marker]).lowercased()) else { return (1, false) }
            isDeal = true
            countEnd = skipSpaces(chars, from: start - 1, step: -1)
        }

        guard let countEnd, chars[countEnd].isASCIIDigit else { return (1, false) }
        var countStart = countEnd
        while countStart > 0, chars[countStart - 1].isASCIIDigit { countStart -= 1 }
        guard let count = Int(String(chars[countStart...countEnd])), (2...99).contains(count) else { return (1, false) }
        return (count, isDeal)
    }

    private static func isUnitPrice(head: String, tail: String) -> Bool {
        let after = #/^\s*[€$£¥]?\s*(\/|per\s|por\s|le\s)\s*(100\s*)?(kg|gr|g|lt|l|ml|cl|un)/#.ignoresCase()
        let before = #/(\/|\bper\b|\bpor\b)\s*(100\s*)?(kg|gr|g|lt|l|ml|cl|un\w*)\.?\s*:?\s*[€$£¥]?\s*$/#.ignoresCase()
        return tail.prefixMatch(of: after) != nil || head.firstMatch(of: before) != nil
    }

    private func skipSpaces(_ chars: [Character], from start: Int, step: Int) -> Int? {
        var cursor = start
        while chars.indices.contains(cursor), chars[cursor] == " " { cursor += step }
        return chars.indices.contains(cursor) ? cursor : nil
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
