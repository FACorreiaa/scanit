import Foundation
import ScanItCore
import SwiftData

/// Turns SwiftData rows into the value snapshots `InsightsCalculator` works on (BACKLOG INS-103).
enum InsightsSource {
    static func calculator(context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> InsightsCalculator {
        let (trips, prices, latestCurrency) = snapshots(context: context)
        // The currency of the latest trip; most people shop in one.
        let currency = latestCurrency ?? Locale.current.currency?.identifier ?? "EUR"
        return InsightsCalculator(trips: trips, prices: prices, currency: currency, now: now, calendar: calendar)
    }

    /// This calendar month's spend in every currency the user has finished a trip in, or has a
    /// budget in (BUD-001). Zero when nothing was spent in it this month. Sorted by currency code.
    static func monthSpend(
        context: ModelContext, alsoIn extra: [String] = [], now: Date = .now, calendar: Calendar = .current
    ) -> [Money] {
        let (trips, _, _) = snapshots(context: context)
        let currencies = Set(trips.map { $0.currency.uppercased() } + extra.map { $0.uppercased() })
        return currencies.sorted().map { currency in
            InsightsCalculator(trips: trips, prices: [], currency: currency, now: now, calendar: calendar)
                .spend(.month).current
        }
    }

    /// Finished trips (newest first), price observations, and the newest trip's currency.
    private static func snapshots(context: ModelContext) -> (trips: [TripSnapshot], prices: [PriceSnapshot], latestCurrency: String?) {
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
        return (trips, prices, sessions.first?.currency)
    }

    /// "en:sweet-spreads" → "Sweet spreads"; "other" → "Other".
    static func categoryTitle(_ tag: String) -> String {
        let bare = tag.split(separator: ":", maxSplits: 1).last.map(String.init) ?? tag
        let words = bare.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
