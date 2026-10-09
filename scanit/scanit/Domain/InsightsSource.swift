import Foundation
import ScanItCore
import SwiftData

/// Turns SwiftData rows into the value snapshots `InsightsCalculator` works on (BACKLOG INS-103).
enum InsightsSource {
    static func calculator(context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> InsightsCalculator {
        let finished = SessionStatus.finished.rawValue
        let sessions = (try? context.fetch(FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { $0.statusRaw == finished && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))) ?? []
        let observations = (try? context.fetch(FetchDescriptor<PriceObservation>(
            predicate: #Predicate { $0.deletedAt == nil }
        ))) ?? []
        let products = (try? context.fetch(FetchDescriptor<Product>())) ?? []
        let categoryByCode = Dictionary(products.map { ($0.gtin, $0.categories.first) }, uniquingKeysWith: { a, _ in a })

        let trips = sessions.map { session in
            TripSnapshot(
                id: session.id.uuidString,
                storeId: session.store?.id.uuidString,
                storeName: session.store?.name,
                currency: session.currency,
                startedAt: session.startedAt,
                endedAt: session.endedAt ?? session.startedAt,
                limitMinor: session.limitMinor,
                tillTotalMinor: session.tillTotalMinor,
                lines: session.liveItems.map { item in
                    LineSnapshot(
                        code: item.code, codeKind: item.scannedCode.kind, name: item.productName,
                        quantity: item.quantity, unitPriceMinor: item.unitPriceMinor,
                        category: categoryByCode[item.code] ?? nil
                    )
                }
            )
        }
        let prices = observations.compactMap { observation -> PriceSnapshot? in
            guard let store = observation.store else { return nil }
            return PriceSnapshot(
                storeId: store.id.uuidString, storeName: store.name, code: observation.code,
                priceMinor: observation.priceMinor, currency: observation.currency, observedAt: observation.observedAt
            )
        }
        // The currency of the latest trip; most people shop in one.
        let currency = sessions.first?.currency ?? Locale.current.currency?.identifier ?? "EUR"
        return InsightsCalculator(trips: trips, prices: prices, currency: currency, now: now, calendar: calendar)
    }

    /// "en:sweet-spreads" → "Sweet spreads"; "other" → "Other".
    static func categoryTitle(_ tag: String) -> String {
        let bare = tag.split(separator: ":", maxSplits: 1).last.map(String.init) ?? tag
        let words = bare.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
