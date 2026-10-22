import Foundation
import ScanItCore
import SwiftData

/// How shelf-price reading is doing on this phone (BACKLOG IOS-007 field metrics), counted from
/// the price source saved on each item. Counts only: no amounts, no names. Until PostHog
/// (FND-004) the owner reads these from the debug section in Insights.
struct OCRStats: Equatable {
    var scanned = 0
    /// The prefilled label price was added unchanged.
    var accepted = 0
    /// The label offered a price and the user changed it in the confirm sheet.
    var edited = 0
    /// Accepted from the label, then corrected later: a wrong price got through.
    var corrected = 0

    /// Items where the label offered a price.
    var read: Int { accepted + edited + corrected }

    /// Target ≥ 70 % of scanned items.
    var acceptedShare: Double? { scanned == 0 ? nil : Double(accepted) / Double(scanned) }
    /// Target ≤ 2 % of label reads.
    var correctedShare: Double? { read == 0 ? nil : Double(corrected) / Double(read) }

    init(items: some Sequence<CartItem>) {
        for item in items where item.deletedAt == nil {
            scanned += 1
            switch item.priceSource {
            case .ocr: accepted += 1
            case .ocrEdited: edited += 1
            case .ocrCorrected: corrected += 1
            case .manual, .remembered, .embedded: break
            }
        }
    }

    static func current(context: ModelContext) -> OCRStats {
        OCRStats(items: (try? context.fetch(FetchDescriptor<CartItem>(predicate: #Predicate { $0.deletedAt == nil }))) ?? [])
    }
}
