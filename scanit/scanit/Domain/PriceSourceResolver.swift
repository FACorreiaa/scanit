import ScanItCore

/// How a shelf-price read went, for `price_ocr_result` (`ARCHITECTURE.md` → Analytics).
nonisolated enum PriceOCROutcome: String, Sendable {
    /// The prefilled label price was added unchanged.
    case accepted
    /// The label offered something, and the user picked another candidate or typed over it.
    case edited
    /// The label gave nothing usable.
    case none
}

/// Where the confirmed price came from (BACKLOG IOS-007). Pure, so the confirm sheet's rule is
/// tested without UI.
nonisolated enum PriceSourceResolver {
    /// - Parameters:
    ///   - prefill: the label price that was filled in, if any.
    ///   - labelCandidates: every item price the label offered as a chip.
    ///   - remembered: the price remembered for this store, if any.
    static func resolve(price: Money, prefill: Money?, labelCandidates: [Money], remembered: Money?) -> PriceSource {
        if let prefill { return price == prefill ? .ocr : .ocrEdited }
        if labelCandidates.contains(price) { return .ocrEdited }
        return price == remembered ? .remembered : .manual
    }

    static func outcome(source: PriceSource, prefill: Money?, labelCandidates: [Money]) -> PriceOCROutcome {
        if source == .ocr { return .accepted }
        return prefill == nil && labelCandidates.isEmpty ? .none : .edited
    }
}
