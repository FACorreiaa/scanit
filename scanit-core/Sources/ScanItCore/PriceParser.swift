import Algorithms
import Foundation

/// One piece of text the scanner recognised on a shelf label.
public struct RecognizedText: Hashable, Sendable {
    public let text: String
    /// Bounding-box height, in any unit as long as it is the same for every item in one frame.
    /// The shelf price is the biggest number on the label, so height is the main ranking signal.
    public let height: Double

    public init(text: String, height: Double) {
        self.text = text
        self.height = height
    }
}

public struct PriceCandidate: Hashable, Sendable {
    /// What the user pays for `quantity` units: `2 x 0,99` is 1,98 for 2; `3 for 5.00` is 5.00 for 3.
    public let total: Money
    public let quantity: Int
    /// A per-kg / per-litre / per-100 g price. Kept so the UI can show it, never picked as best.
    public let isUnitPrice: Bool
    public let hasCurrencySymbol: Bool
    public let sourceText: String
    public let height: Double
    /// 0…1. Low when another price on the label is almost as big. The user always confirms.
    public let confidence: Double
}

public struct PriceParseResult: Sendable {
    /// Prices first (best first), unit prices last.
    public let candidates: [PriceCandidate]

    public var best: PriceCandidate? {
        candidates.first { !$0.isUnitPrice }
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

    public func parse(_ items: [RecognizedText]) -> PriceParseResult {
        let (shelfPrices, unitPrices) = items.flatMap(amounts(in:)).partitioned(by: \.isUnitPrice)
        let prices = shelfPrices.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.height != rhs.element.height { return lhs.element.height > rhs.element.height }
                if lhs.element.hasSymbol != rhs.element.hasSymbol { return lhs.element.hasSymbol }
                return lhs.offset < rhs.offset
            }
            .map(\.element)

        let confidence = bestConfidence(prices)
        let ranked = prices.enumerated().map { index, amount in
            amount.candidate(currency: currency, confidence: index == 0 ? confidence : 0)
        } + unitPrices.map { $0.candidate(currency: currency, confidence: 0) }
        return PriceParseResult(candidates: ranked)
    }

    private func bestConfidence(_ prices: [FoundAmount]) -> Double {
        guard let best = prices.first else { return 0 }
        let base = best.hasSymbol && best.hasDecimals ? 0.95 : 0.85
        guard let second = prices.dropFirst().first, best.height > 0 else { return base }
        let ratio = second.height / best.height
        return base * min(1, max(0, 0.4 + (1 - ratio) * 2))
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

        func candidate(currency: String, confidence: Double) -> PriceCandidate {
            let unit = Money(amountMinor: amountMinor, currency: currency)
            return PriceCandidate(
                total: isDeal ? unit : unit.multiplied(by: quantity),
                quantity: quantity,
                isUnitPrice: isUnitPrice,
                hasCurrencySymbol: hasSymbol,
                sourceText: sourceText,
                height: height,
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
                height: item.height
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
