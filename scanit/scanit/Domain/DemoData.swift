#if DEBUG
import Foundation
import ScanItCore
import SwiftData

/// Debug-only sample history: four weeks of trips at two stores, for UI tests
/// (`-ui-testing-demo-data`) and screenshots. Never compiled into release builds.
enum DemoData {
    static func seed(_ context: ModelContext, now: Date = .now) {
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        let continente = Store(name: "Continente", countryCode: "PT", currency: "EUR")
        context.insert(lidl)
        context.insert(continente)

        let products: [(code: String, name: String, category: String)] = [
            ("05601234567892", "Leite meio gordo", "en:milks"),
            ("04006381333931", "Pão de forma", "en:breads"),
            ("03017620422003", "Nutella", "en:sweet-spreads"),
            ("05600000000007", "Iogurte natural", "en:yogurts"),
            ("05601111111116", "Café moído", "en:coffees"),
        ]
        for product in products {
            let row = Product(gtin: product.code)
            row.name = product.name
            row.categories = [product.category]
            row.offFetchedAt = now
            context.insert(row)
        }

        // (days ago, store, limit, [(product index, quantity, price)])
        let trips: [(Int, Store, Int?, [(Int, Int, Int)])] = [
            (27, lidl, 5000, [(0, 4, 89), (1, 1, 129), (2, 1, 399), (3, 6, 45)]),
            (20, continente, 6000, [(0, 4, 99), (2, 1, 429), (4, 1, 549), (3, 4, 49)]),
            (13, lidl, 5000, [(0, 4, 95), (1, 2, 129), (4, 1, 499), (3, 6, 45)]),
            (6, continente, 4000, [(0, 4, 99), (2, 2, 429), (1, 1, 149), (4, 1, 549)]),
            (2, lidl, 5000, [(0, 6, 99), (1, 1, 139), (2, 1, 409), (3, 6, 49), (4, 1, 519)]),
        ]
        for (daysAgo, store, limit, lines) in trips {
            let start = now.addingTimeInterval(-Double(daysAgo) * 86_400)
            let session = ShoppingSession(store: store, limitMinor: limit, currency: "EUR", now: start)
            session.status = .finished
            session.endedAt = start.addingTimeInterval(1800)
            context.insert(session)
            for (index, quantity, price) in lines {
                let product = products[index]
                let item = CartItem(
                    code: ScannedCode(kind: .gtin, value: product.code), productName: product.name,
                    quantity: quantity, unitPriceMinor: price, priceSource: .manual, now: start
                )
                context.insert(item)
                item.session = session
                context.insert(PriceObservation(
                    store: store, code: product.code, price: Money(amountMinor: price, currency: "EUR"),
                    source: .manual, now: start
                ))
            }
        }
        try? context.save()
    }
}
#endif
