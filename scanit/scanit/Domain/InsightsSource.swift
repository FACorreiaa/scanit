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

        let trips = sessions.map { snapshot($0, categoryByCode: categoryByCode) }
        return (trips, priceSnapshots(observations), sessions.first?.currency)
    }

    private static func snapshot(_ session: ShoppingSession, categoryByCode: [String: String?] = [:]) -> TripSnapshot {
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

    /// INS-12/13 for each finished trip given (SAVE-002), keyed by trip id. Prices are fetched once,
    /// and each trip is measured in its own currency, so a dollar trip is never dropped for not
    /// being in euros. Trips with no product priced at another store are left out.
    static func tripSavings(_ sessions: [ShoppingSession], context: ModelContext) -> [UUID: TripSavingSummary] {
        guard !sessions.isEmpty else { return [:] }
        let prices = prices(context: context)
        var calculators: [String: InsightsCalculator] = [:]
        var result: [UUID: TripSavingSummary] = [:]
        for session in sessions {
            let currency = session.currency.uppercased()
            let calculator = calculators[currency]
                ?? InsightsCalculator(trips: [], prices: prices, currency: currency, now: .now)
            calculators[currency] = calculator
            if let saving = calculator.tripSaving(snapshot(session)).flatMap(TripSavingSummary.init) {
                result[session.id] = saving
            }
        }
        return result
    }

    /// Every price the user has seen, for meal costs (MEAL-001) and comparisons.
    static func prices(context: ModelContext) -> [PriceSnapshot] {
        priceSnapshots((try? context.fetch(FetchDescriptor<PriceObservation>(predicate: #Predicate { $0.deletedAt == nil }))) ?? [])
    }

    /// The currency the user shops in: the newest finished trip's, else the phone's.
    static func homeCurrency(context: ModelContext) -> String {
        let finished = SessionStatus.finished.rawValue
        var descriptor = FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { $0.statusRaw == finished && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.currency ?? Locale.current.currency?.identifier ?? "EUR"
    }

    private static func priceSnapshots(_ observations: [PriceObservation]) -> [PriceSnapshot] {
        observations.compactMap { observation -> PriceSnapshot? in
            guard let store = observation.store else { return nil }
            return PriceSnapshot(
                storeId: store.id.uuidString, storeName: store.name, code: observation.code,
                priceMinor: observation.priceMinor, currency: observation.currency, observedAt: observation.observedAt
            )
        }
    }

    /// "en:sweet-spreads" → "Sweet spreads"; "other" → "Other".
    static func categoryTitle(_ tag: String) -> String {
        let bare = tag.split(separator: ":", maxSplits: 1).last.map(String.init) ?? tag
        let words = bare.replacingOccurrences(of: "-", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
