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

    /// A trip in progress for App Store screenshots: named products at Lidl, €60 limit, nearly reached.
    static func seedActiveTrip(_ context: ModelContext, now: Date = .now) {
        let lidl = (try? context.fetch(FetchDescriptor<Store>()))?.first { $0.name == "Lidl" }
            ?? Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        if lidl.modelContext == nil { context.insert(lidl) }
        let session = ShoppingSession(store: lidl, limitMinor: 6000, currency: "EUR", now: now.addingTimeInterval(-1500))
        context.insert(session)
        let lines: [(String, String, Int, Int)] = [
            ("05601234567892", "Leite meio gordo", 6, 99),
            ("03017620422003", "Nutella", 1, 409),
            ("05601111111116", "Café moído", 2, 519),
            ("05600000000007", "Iogurte natural", 6, 49),
            ("04006381333931", "Pão de forma", 1, 139),
            ("05602222222226", "Azeite virgem extra 750 ml", 1, 899),
            ("05603333333336", "Queijo flamengo fatiado", 2, 249),
            ("05604444444446", "Bananas da Madeira", 1, 312),
            ("05605555555556", "Detergente líquido 1,5 l", 1, 699),
        ]
        for (index, (code, name, quantity, price)) in lines.enumerated() {
            let item = CartItem(
                code: ScannedCode(kind: .gtin, value: code), productName: name, quantity: quantity,
                unitPriceMinor: price, priceSource: index % 3 == 0 ? .remembered : .manual,
                now: now.addingTimeInterval(Double(index - lines.count) * 90)
            )
            context.insert(item)
            item.session = session
        }
        try? context.save()
    }
}
#endif
