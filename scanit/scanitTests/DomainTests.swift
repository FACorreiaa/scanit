import Foundation
import ScanItCore
import SwiftData
import Testing
import UIKit
@testable import scanit

private let milk = ScannedCode(kind: .gtin, value: "05601234567892")
private let bread = ScannedCode(kind: .gtin, value: "04006381333931")

/// Records analytics so tests can assert on events.
private final class RecordingAnalytics: AnalyticsClient, @unchecked Sendable {
    var events: [AnalyticsEvent] = []
    func track(_ event: AnalyticsEvent) { events.append(event) }
}

@MainActor
private func makeContext() throws -> ModelContext {
    ModelContext(try ScanItSchema.container(inMemory: true))
}

// MARK: - IOS-001

@MainActor
struct ModelTests {
    @Test func totalInMinorUnitsExcludesSoftDeletedItems() throws {
        let context = try makeContext()
        let store = Store(name: "Lidl", countryCode: "PT", currency: "eur")
        let session = ShoppingSession(store: store, limitMinor: 6000, currency: "EUR")
        context.insert(session)

        let a = CartItem(code: milk, quantity: 2, unitPriceMinor: 99, priceSource: .ocr)
        let b = CartItem(code: bread, unitPriceMinor: 149, priceSource: .manual)
        context.insert(a); context.insert(b)
        a.session = session; b.session = session
        try context.save()

        #expect(session.totalMinor == 347)
        #expect(session.total == Money(amountMinor: 347, currency: "EUR"))
        #expect(store.currency == "EUR")

        b.softDelete()
        #expect(session.totalMinor == 198)
        #expect(session.liveItems.count == 1)
        #expect(session.items.count == 2, "soft delete keeps the row for sync")
        #expect(b.syncStateRaw == SyncState.dirty.rawValue)
    }

    @Test func enumsRoundTripThroughRawStrings() throws {
        let item = CartItem(code: milk, unitPriceMinor: 99, priceSource: .remembered)
        #expect(item.priceSource == .remembered)
        #expect(item.scannedCode == milk)
        let session = ShoppingSession(store: nil, limitMinor: nil, currency: "EUR")
        #expect(session.status == .active)
        session.status = .finished
        #expect(session.statusRaw == "finished")
    }
}

// MARK: - IOS-002

@MainActor
struct SessionStoreTests {
    @Test func startsTripsWithAndWithoutLimit() throws {
        let context = try makeContext()
        let analytics = RecordingAnalytics()
        let store = SessionStore(context: context, analytics: analytics)

        let limited = store.startTrip(store: nil, limitMinor: 6000, currency: "EUR")
        #expect(store.active === limited)
        #expect(store.limitState == .ok)

        let unlimited = store.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        #expect(store.limitState == .noLimit)
        #expect(limited.status == .abandoned, "only one trip is ever active")
        #expect(unlimited.status == .active)
        #expect(analytics.events == [.tripStarted(hasLimit: true), .tripStarted(hasLimit: false)])
    }

    @Test func hapticFiresExactlyOncePerCrossing() throws {
        let context = try makeContext()
        let store = SessionStore(context: context, analytics: RecordingAnalytics())
        store.startTrip(store: nil, limitMinor: 10000, currency: "EUR")
        var fired: [LimitFeedback] = []
        var lastID: UUID?
        func record() {
            if let event = store.feedback, event.id != lastID {
                fired.append(event.kind)
                lastID = event.id
            }
        }

        store.addItem(code: milk, unitPriceMinor: 7999, priceSource: .manual); record()   // 79.99 %
        #expect(store.limitState == .ok)
        let cent = store.addItem(code: bread, unitPriceMinor: 1, priceSource: .manual); record() // 80 %
        #expect(store.limitState == .near)
        store.addItem(code: bread, unitPriceMinor: 2000, priceSource: .manual); record() // 100 %
        #expect(store.limitState == .near)
        let over = store.addItem(code: bread, unitPriceMinor: 1, priceSource: .manual); record() // 100.01 %
        #expect(store.limitState == .over)
        #expect(fired == [.warning, .error])

        // Back under is silent; crossing again speaks again.
        store.remove(try #require(over)); record()
        store.remove(try #require(cent)); record()
        #expect(store.limitState == .near)
        #expect(fired == [.warning, .error])
        store.addItem(code: milk, unitPriceMinor: 50, priceSource: .manual); record()
        #expect(store.limitState == .over)
        #expect(fired == [.warning, .error, .error])
    }

    @Test func editingQuantityAndPriceUpdatesTotal() throws {
        let context = try makeContext()
        let store = SessionStore(context: context, analytics: RecordingAnalytics())
        store.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        let item = try #require(store.addItem(code: milk, unitPriceMinor: 99, priceSource: .ocr))

        store.update(item, quantity: 3)
        #expect(store.active?.totalMinor == 297)
        store.update(item, unitPriceMinor: 89)
        #expect(store.active?.totalMinor == 267)
        #expect(item.priceSource == .ocrCorrected, "a corrected label price is counted as a correction")
        store.update(item, quantity: 0)
        #expect(item.quantity == 1)
    }

    @Test func activeTripSurvivesRelaunch() throws {
        let container = try ScanItSchema.container(inMemory: true)
        let first = SessionStore(context: ModelContext(container), analytics: RecordingAnalytics())
        let trip = first.startTrip(store: nil, limitMinor: 5000, currency: "EUR")
        first.addItem(code: milk, unitPriceMinor: 4500, priceSource: .manual)

        let second = SessionStore(context: ModelContext(container), analytics: RecordingAnalytics())
        #expect(second.active?.id == trip.id)
        #expect(second.limitState == .near)
    }

    @Test func cancelEndsTheTrip() throws {
        let context = try makeContext()
        let store = SessionStore(context: context, analytics: RecordingAnalytics())
        let trip = store.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        store.cancelTrip()
        #expect(store.active == nil)
        #expect(trip.status == .abandoned)
        #expect(trip.endedAt != nil)
    }
}

// MARK: - IOS-003

@MainActor
struct TripStartOptionsTests {
    @Test func firstUseHasNothingToSuggest() throws {
        let options = TripStartOptions(context: try makeContext())
        #expect(options.recentStores.isEmpty)
        #expect(options.lastUsedStore == nil)
        #expect(options.limitSuggestions(currency: "EUR").isEmpty)
    }

    @Test func lastUsedStoreIsPreselectedAndFirst() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        let continente = Store(name: "Continente", countryCode: "PT", currency: "EUR")
        let neverVisited = Store(name: "Mercadona", countryCode: "PT", currency: "EUR")
        [lidl, continente, neverVisited].forEach(context.insert)

        let base = Date(timeIntervalSince1970: 1_790_000_000)
        let store = SessionStore(context: context, analytics: RecordingAnalytics(), now: { base })
        store.startTrip(store: continente, limitMinor: nil, currency: "EUR")
        store.cancelTrip()
        let later = SessionStore(context: context, analytics: RecordingAnalytics(), now: { base + 3600 })
        later.startTrip(store: lidl, limitMinor: nil, currency: "EUR")

        let options = TripStartOptions(context: context, now: base + 7200)
        #expect(options.lastUsedStore?.name == "Lidl")
        #expect(options.recentStores.map(\.name) == ["Lidl", "Continente", "Mercadona"])
    }

    @Test func limitChipsComeFromHistory() throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        func finishedTrip(limit: Int?, total: Int, daysAgo: Int) {
            let session = ShoppingSession(store: nil, limitMinor: limit, currency: "EUR",
                                          now: now - Double(daysAgo) * 86_400)
            session.status = .finished
            session.endedAt = session.startedAt + 1800
            context.insert(session)
            let item = CartItem(code: milk, unitPriceMinor: total, priceSource: .manual)
            context.insert(item)
            item.session = session
        }
        finishedTrip(limit: 6000, total: 4250, daysAgo: 3)
        finishedTrip(limit: nil, total: 5110, daysAgo: 10)
        finishedTrip(limit: nil, total: 99_999, daysAgo: 200) // outside the 90-day window
        try context.save()

        let chips = TripStartOptions(context: context, now: now).limitSuggestions(currency: "EUR")
        #expect(chips.map(\.kind) == [.lastLimit, .averageTrip])
        #expect(chips[0].amount == Money(amountMinor: 6000, currency: "EUR"))
        // (4250 + 5110) / 2 = 4680, rounded up to a whole euro.
        #expect(chips[1].amount == Money(amountMinor: 4700, currency: "EUR"))
        #expect(TripStartOptions(context: context, now: now).limitSuggestions(currency: "USD").isEmpty)
    }
}

// MARK: - IOS-008 / IOS-009: recording and remembering prices

@MainActor
struct PriceMemoryTests {
    @Test func secondScanInSameStoreIsPrefilledOtherStoreIsNot() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        let aldi = Store(name: "Aldi", countryCode: "PT", currency: "EUR")
        context.insert(lidl); context.insert(aldi)
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let store = SessionStore(context: context, analytics: RecordingAnalytics(), now: { clock })

        store.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        #expect(PriceMemory.lookup(code: milk.value, store: lidl, context: context) == nil)
        store.addItem(code: milk, unitPriceMinor: 99, priceSource: .manual)

        clock += 12 * 86_400
        let remembered = try #require(PriceMemory.lookup(code: milk.value, store: lidl, context: context))
        #expect(remembered.price == Money(amountMinor: 99, currency: "EUR"))
        #expect(remembered.observedAt == clock - 12 * 86_400)
        #expect(PriceMemory.lookup(code: milk.value, store: aldi, context: context) == nil)
    }

    @Test func newestPriceWinsIncludingCorrections() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        context.insert(lidl)
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let store = SessionStore(context: context, analytics: RecordingAnalytics(), now: { clock })
        store.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        let item = try #require(store.addItem(code: milk, unitPriceMinor: 99, priceSource: .ocr))
        clock += 60
        store.update(item, unitPriceMinor: 109)
        #expect(PriceMemory.lookup(code: milk.value, store: lidl, context: context)?.price.amountMinor == 109)

        clock += 60
        store.update(item, quantity: 2) // no price change → no new observation
        let all = try context.fetch(FetchDescriptor<PriceObservation>())
        #expect(all.count == 2)
    }

    @Test func tripWithoutStoreRemembersNothing() throws {
        let context = try makeContext()
        let store = SessionStore(context: context, analytics: RecordingAnalytics())
        store.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        store.addItem(code: milk, unitPriceMinor: 99, priceSource: .manual)
        #expect(try context.fetch(FetchDescriptor<PriceObservation>()).isEmpty)
    }
}

// MARK: - Zero-tap scan: undo and the cheaper-elsewhere hint

@MainActor
struct ZeroTapScanTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    /// Buys milk at `store` for `minor` on its own finished trip.
    private func buy(_ minor: Int, at store: Store, with sessions: SessionStore, code: ScannedCode = milk) {
        sessions.startTrip(store: store, limitMinor: nil, currency: store.currency)
        sessions.addItem(code: code, unitPriceMinor: minor, priceSource: .manual)
        sessions.finishTrip()
    }

    @Test func undoRemovesTheItemAndForgetsItsPrice() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        context.insert(lidl)
        var clock = start
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics(), now: { clock })
        buy(99, at: lidl, with: sessions)

        clock += 86_400
        let trip = sessions.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        let misread = try #require(sessions.addItem(code: milk, unitPriceMinor: 9_900, priceSource: .ocr))
        clock += 5
        sessions.update(misread, quantity: 2)
        sessions.undoAdd(misread)

        #expect(trip.totalMinor == 0)
        #expect(PriceMemory.lookup(code: milk.value, store: lidl, context: context)?.price.amountMinor == 99,
                "the price from before the undone add is the remembered one again")
    }

    @Test func cheapestOtherStoreByItsNewestPrice() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        let aldi = Store(name: "Aldi", countryCode: "PT", currency: "EUR")
        let pingo = Store(name: "Pingo Doce", countryCode: "PT", currency: "EUR")
        [lidl, aldi, pingo].forEach(context.insert)
        var clock = start
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics(), now: { clock })
        buy(79, at: aldi, with: sessions) // an old Aldi price, since replaced
        clock += 86_400
        buy(95, at: aldi, with: sessions)
        buy(89, at: pingo, with: sessions)
        buy(50, at: lidl, with: sessions) // the store being shopped in never counts
        clock += 86_400

        let found = try #require(PriceMemory.cheapestElsewhere(
            code: milk, store: lidl, currency: "EUR", context: context, now: clock
        ))
        #expect(found.storeName == "Pingo Doce")
        #expect(found.price == Money(amountMinor: 89, currency: "EUR"))
        #expect(found.isCheaper(than: Money(amountMinor: 99, currency: "EUR")))
        #expect(!found.isCheaper(than: Money(amountMinor: 89, currency: "EUR")))
        #expect(!found.isCheaper(than: nil))
    }

    @Test func staleForeignAndInStorePricesAreIgnored() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        let aldi = Store(name: "Aldi", countryCode: "PT", currency: "EUR")
        let tesco = Store(name: "Tesco", countryCode: "GB", currency: "GBP")
        [lidl, aldi, tesco].forEach(context.insert)
        var clock = start
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics(), now: { clock })
        let weighed = ScannedCode(kind: .gtin, value: "02012345001996")
        #expect(weighed.isInStore)
        buy(79, at: aldi, with: sessions)
        buy(60, at: tesco, with: sessions)
        buy(120, at: aldi, with: sessions, code: weighed)

        func elsewhere(_ code: ScannedCode) -> PriceElsewhere? {
            PriceMemory.cheapestElsewhere(code: code, store: lidl, currency: "EUR", context: context, now: clock)
        }
        #expect(elsewhere(milk)?.storeName == "Aldi", "pounds are not compared with euros")
        #expect(elsewhere(weighed) == nil, "an in-store code is another product in another shop")

        clock += PriceMemory.elsewhereMaxAge + 86_400
        #expect(elsewhere(milk) == nil, "a price from months ago is not offered")
    }
}

// MARK: - ADD-002: share a trip

@MainActor
struct TripShareTests {
    private func content(total: Int, limit: Int?, items: Int = 3, store: String? = "Lidl") -> TripShareContent {
        TripShareContent(
            storeName: store, date: Date(timeIntervalSince1970: 1_790_000_000),
            total: Money(amountMinor: total, currency: "EUR"),
            limit: limit.map { Money(amountMinor: $0, currency: "EUR") }, itemCount: items
        )
    }

    @Test func resultSaysUnderOverOrNothing() {
        let euro = { (minor: Int) in Money(amountMinor: minor, currency: "EUR").formatted() }
        #expect(content(total: 4280, limit: 6000).result == "\(euro(1720)) under my \(euro(6000)) limit")
        #expect(content(total: 6340, limit: 6000).result == "\(euro(340)) over my \(euro(6000)) limit")
        #expect(content(total: 6000, limit: 6000).result == "Right on my \(euro(6000)) limit")
        #expect(content(total: 4280, limit: nil).result == nil)
        #expect(content(total: 4280, limit: nil).progress == nil)
        #expect(content(total: 9000, limit: 6000).progress == 1)
        #expect(content(total: 9000, limit: 6000).isOver)
    }

    @Test func itemsAndCaption() {
        #expect(content(total: 100, limit: nil, items: 1).items == "1 item")
        #expect(content(total: 100, limit: nil, items: 12).items == "12 items")
        #expect(content(total: 100, limit: nil).caption.contains("at Lidl"))
        #expect(!content(total: 100, limit: nil, store: nil).caption.contains(" at "))
    }

    @Test func comesFromAFinishedTripWithoutProductNames() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        context.insert(lidl)
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
        sessions.startTrip(store: lidl, limitMinor: 500, currency: "EUR")
        sessions.addItem(code: milk, productName: "Leite", quantity: 2, unitPriceMinor: 99, priceSource: .manual)
        let trip = try #require(sessions.finishTrip())

        let shared = TripShareContent(session: trip)
        #expect(shared.total.amountMinor == 198)
        #expect(shared.itemCount == 2)
        #expect(shared.storeName == "Lidl")
        #expect(!"\(shared)".contains("Leite"))
    }

    @Test func shortcutRequestIsTakenOnce() {
        let actions = ShortcutActions()
        #expect(!actions.takeStartShopping())
        actions.requestStartShopping()
        #expect(actions.takeStartShopping())
        #expect(!actions.takeStartShopping())
    }

    @Test func cardRendersAtShareSize() throws {
        for (name, sample) in [("under", content(total: 4280, limit: 6000, items: 23)),
                               ("over", content(total: 6340, limit: 6000, items: 31)),
                               ("nolimit", content(total: 1999, limit: nil, items: 1, store: nil))] {
            Attachment.record(try #require(TripShareCard.png(sample)), named: "share-\(name).png")
        }
        let data = try #require(TripShareCard.png(content(total: 123_456, limit: 6000)))
        let image = try #require(UIImage(data: data))
        #expect(image.size == CGSize(width: 1080, height: 1350))
    }
}

// MARK: - ADD-003: monthly budget

@MainActor
struct BudgetStoreTests {
    private func freshDefaults() throws -> UserDefaults {
        let suite = "scanit.tests.budget.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func budgetSurvivesRelaunchAndCanBeRemoved() throws {
        let defaults = try freshDefaults()
        let store = BudgetStore(defaults: defaults)
        #expect(store.budget == nil)

        store.set(Money(amountMinor: 40_000, currency: "EUR"))
        #expect(BudgetStore(defaults: defaults).budget == Money(amountMinor: 40_000, currency: "EUR"))

        store.set(Money(amountMinor: 0, currency: "EUR"))
        #expect(store.budget == nil)
        #expect(BudgetStore(defaults: defaults).budget == nil)
    }

    @Test func statusUsesTheTripLimitThresholds() throws {
        let store = BudgetStore(defaults: try freshDefaults())
        let euro = { (minor: Int) in Money(amountMinor: minor, currency: "EUR") }
        #expect(store.status(spent: euro(100)) == nil, "no budget, no status")

        store.set(euro(40_000))
        #expect(store.status(spent: euro(10_000))?.state == .ok)
        #expect(store.status(spent: euro(32_000))?.state == .near)
        #expect(store.status(spent: euro(40_001))?.state == .over)
        #expect(store.status(spent: euro(40_001))?.remainingMinor == -1)
        #expect(store.status(spent: Money(amountMinor: 100, currency: "GBP")) == nil, "other currency is not compared")
    }
}

// MARK: - ADD-006: export trips

@MainActor
struct TripExportTests {
    @Test func oneRowPerLineWithPlainAmountsAndQuoting() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let rows = [
            TripExport.Row(date: date, store: "Pingo Doce, Baixa", product: "Leite \"meio gordo\"", code: "05601234567892",
                           quantity: 2, unitPriceMinor: 99, currency: "EUR", priceSource: "ocr"),
            TripExport.Row(date: date, store: "Lidl", product: "=HYPERLINK(1)", code: "04006381333931",
                           quantity: 1, unitPriceMinor: 1205, currency: "EUR", priceSource: "manual"),
        ]
        let lines = TripExport.csv(rows, timeZone: TimeZone(identifier: "UTC")!).components(separatedBy: "\r\n")
        #expect(lines[0] == "date,store,product,code,quantity,unit_price,line_total,currency,price_source")
        #expect(lines[1] == "2026-09-21 14:13:20,\"Pingo Doce, Baixa\",\"Leite \"\"meio gordo\"\"\",05601234567892,2,0.99,1.98,EUR,ocr")
        #expect(lines[2] == "2026-09-21 14:13:20,Lidl,'=HYPERLINK(1),04006381333931,1,12.05,12.05,EUR,manual")
        #expect(lines.count == 4 && lines[3].isEmpty, "ends with a line break")
    }

    @Test func exportsFinishedTripsOnlyWithoutDeletedLines() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        context.insert(lidl)
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics(), now: { clock })
        sessions.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        sessions.addItem(code: milk, productName: "Leite", quantity: 2, unitPriceMinor: 99, priceSource: .manual)
        clock += 10
        let removed = try #require(sessions.addItem(code: bread, unitPriceMinor: 149, priceSource: .manual))
        sessions.remove(removed)
        sessions.finishTrip()
        clock += 86_400
        sessions.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        sessions.addItem(code: bread, unitPriceMinor: 149, priceSource: .manual)

        let rows = TripExport.rows(context: context)
        #expect(rows.count == 1)
        #expect(rows.first?.product == "Leite")
        #expect(rows.first?.quantity == 2)
    }
}

// MARK: - ADD-005: shopping list

@MainActor
struct ShoppingListTests {
    @Test func addIgnoresBlanksAndRepeats() throws {
        let context = try makeContext()
        #expect(ShoppingList.add("  ", context: context) == nil)
        #expect(ShoppingList.add(" Leite ", context: context)?.text == "Leite")
        #expect(ShoppingList.add("leite", context: context) == nil, "already waiting")
        #expect(ShoppingList.lines(context: context).count == 1)
    }

    @Test(arguments: [
        ("leite", "Leite meio gordo · Mimosa", true),
        ("pao forma", "Pão de forma", true),
        ("Leite gordo", "Leite meio gordo", true),
        ("leite magro", "Leite meio gordo", false),
        ("de", "Pão de forma", false),
        ("eite", "Leite meio gordo", false),
    ])
    func nameMatching(line: String, product: String, expected: Bool) {
        #expect(ShoppingList.matches(line: line, productName: product) == expected)
    }

    @Test func scanTicksByCodeThenByNameAndFinishClearsTicked() throws {
        let context = try makeContext()
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
        let byCode = try #require(ShoppingList.add("Pão de forma", code: bread.value, context: context))
        let byName = try #require(ShoppingList.add("leite", context: context))
        let untouched = try #require(ShoppingList.add("ovos", context: context))

        sessions.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        sessions.addItem(code: bread, unitPriceMinor: 149, priceSource: .manual)
        #expect(byCode.isDone)
        #expect(!byName.isDone)

        sessions.addItem(code: milk, productName: "Leite meio gordo", unitPriceMinor: 99, priceSource: .manual)
        #expect(byName.isDone)
        #expect(!untouched.isDone)

        sessions.finishTrip()
        let left = ShoppingList.lines(context: context)
        #expect(left.map(\.text) == ["ovos"], "ticked lines leave the list with the trip")
    }

    @Test func aNameArrivingLaterTicksTheLine() async throws {
        let context = try makeContext()
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
        let line = try #require(ShoppingList.add("leite", context: context))
        sessions.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        let item = try #require(sessions.addItem(code: milk, unitPriceMinor: 99, priceSource: .manual))
        #expect(!line.isDone)

        let enricher = ProductEnricher(context: context, lookup: FixedProductLookup(names: ["5601234567892": "Leite meio gordo"]))
        enricher.enqueue(item)
        await enricher.flush()
        #expect(item.productName == "Leite meio gordo")
        #expect(line.isDone)
    }

    @Test func suggestionsComeFromNamedPastProducts() throws {
        let context = try makeContext()
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
        sessions.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        sessions.addItem(code: milk, productName: "Leite meio gordo", unitPriceMinor: 99, priceSource: .manual)
        sessions.addItem(code: milk, productName: "Leite meio gordo", unitPriceMinor: 99, priceSource: .manual)
        sessions.addItem(code: bread, unitPriceMinor: 149, priceSource: .manual)

        #expect(ShoppingList.suggestions(for: "lei", context: context) == [ListSuggestion(code: milk.value, name: "Leite meio gordo")])
        #expect(ShoppingList.suggestions(for: "l", context: context).isEmpty)
        #expect(ShoppingList.suggestions(for: "pao", context: context).isEmpty, "unnamed products are not offered")
    }
}

// MARK: - LIVE-001: Live Activity

@MainActor
struct TripActivityTests {
    private let euro = { (minor: Int) in Money(amountMinor: minor, currency: "EUR").formatted() }

    @Test func contentFollowsTheTripAndItsLimit() throws {
        let context = try makeContext()
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
        let trip = sessions.startTrip(store: nil, limitMinor: 1000, currency: "EUR")
        sessions.addItem(code: milk, quantity: 2, unitPriceMinor: 200, priceSource: .manual)

        var state = TripActivityAttributes.ContentState(session: trip)
        #expect(state.total == euro(400))
        #expect(state.limitText == "\(euro(600)) left of \(euro(1000))")
        #expect(state.progress == 0.4)
        #expect(state.level == .ok)
        #expect(state.items == 2)

        sessions.addItem(code: bread, unitPriceMinor: 500, priceSource: .manual)
        #expect(TripActivityAttributes.ContentState(session: trip).level == .near)

        sessions.addItem(code: bread, unitPriceMinor: 500, priceSource: .manual)
        state = TripActivityAttributes.ContentState(session: trip)
        #expect(state.limitText == "\(euro(400)) over \(euro(1000))")
        #expect(state.progress == 1)
        #expect(state.level == .over)
    }

    @Test func withoutALimitThereIsOnlyATotal() throws {
        let context = try makeContext()
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
        let trip = sessions.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        sessions.addItem(code: milk, unitPriceMinor: 99, priceSource: .manual)
        let state = TripActivityAttributes.ContentState(session: trip)
        #expect(state.limitText == nil)
        #expect(state.progress == nil)
        #expect(state.level == .noLimit)
    }

    @Test func storeReportsEveryChangeAndTheEnd() throws {
        let context = try makeContext()
        var reported: [Int?] = []
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics(), onTripChange: { reported.append($0?.totalMinor) })
        #expect(reported == [nil], "nothing in progress at launch")

        sessions.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        let item = try #require(sessions.addItem(code: milk, unitPriceMinor: 100, priceSource: .manual))
        sessions.update(item, quantity: 3)
        sessions.remove(item)
        sessions.addItem(code: bread, unitPriceMinor: 150, priceSource: .manual)
        let finished = try #require(sessions.finishTrip())
        #expect(reported == [nil, 0, 100, 300, 0, 150, nil])

        sessions.undoFinish(finished)
        sessions.cancelTrip()
        #expect(reported.suffix(2) == [150, nil])
    }
}

// MARK: - IOS-010: finish, summary, undo

@MainActor
struct FinishTripTests {
    @Test func finishProducesSummaryAndUndoRestores() throws {
        let context = try makeContext()
        let analytics = RecordingAnalytics()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        context.insert(lidl)
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let store = SessionStore(context: context, analytics: analytics, now: { clock })

        // A previous trip at Lidl: €30.00.
        store.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        store.addItem(code: bread, unitPriceMinor: 3000, priceSource: .manual)
        store.finishTrip()

        clock += 86_400
        store.startTrip(store: lidl, limitMinor: 5000, currency: "EUR")
        #expect(store.finishTrip() == nil, "an empty trip cannot be finished")
        store.addItem(code: milk, quantity: 2, unitPriceMinor: 99, priceSource: .manual)
        store.addItem(code: bread, unitPriceMinor: 3500, priceSource: .manual)
        store.addItem(code: ScannedCode(kind: .gtin, value: "00000096385074"), unitPriceMinor: 450, priceSource: .manual)
        store.addItem(code: ScannedCode(kind: .opaque, value: "promo"), unitPriceMinor: 10, priceSource: .manual)

        let trip = try #require(store.finishTrip())
        #expect(store.active == nil)
        #expect(trip.status == .finished)
        #expect(analytics.events.last == .tripFinished(items: 5, underLimit: true))

        let summary = TripSummary(session: trip, context: context)
        #expect(summary.total.amountMinor == 4158)
        #expect(summary.itemCount == 5)
        #expect(summary.biggestLines.map(\.unitPriceMinor) == [3500, 450, 99])
        #expect(summary.previousTotalAtStore?.amountMinor == 3000)
        #expect(summary.deltaVsPrevious?.amountMinor == 1158)

        store.setTillTotal(trip, minor: 4200)
        #expect(trip.tillTotalMinor == 4200)

        store.undoFinish(trip)
        #expect(store.active === trip)
        #expect(trip.status == .active)
        #expect(trip.endedAt == nil)
    }
}

// MARK: - Typed amounts

struct MoneyInputTests {
    @Test(arguments: [
        ("60", 6000), ("60,5", 6050), ("60.50", 6050), (" 1,99 ", 199), ("0,999", 100),
    ])
    func parses(text: String, minor: Int) {
        #expect(MoneyInput.parse(text, currency: "EUR") == Money(amountMinor: minor, currency: "EUR"))
    }

    @Test(arguments: ["", "abc", "1,2,3", "€5", "-3"])
    func rejects(text: String) {
        #expect(MoneyInput.parse(text, currency: "EUR") == nil)
    }

    @Test func editingTextRoundTrips() {
        let money = Money(amountMinor: 199, currency: "EUR")
        #expect(MoneyInput.editingText(money, locale: Locale(identifier: "pt_PT")) == "1,99")
        #expect(MoneyInput.parse(MoneyInput.editingText(money, locale: Locale(identifier: "pt_PT")), currency: "EUR") == money)
    }
}

// MARK: - IOS-011: history grouping

@MainActor
struct HistoryGroupingTests {
    @Test func groupsByMonthNewestFirstWithPerCurrencyTotals() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        func trip(_ day: String, _ minor: Int, _ currency: String = "EUR") -> ShoppingSession {
            let date = try! Date("\(day)T10:00:00Z", strategy: .iso8601)
            let session = ShoppingSession(store: nil, limitMinor: nil, currency: currency, now: date)
            let item = CartItem(code: milk, unitPriceMinor: minor, priceSource: .manual)
            item.session = session
            session.items = [item]
            return session
        }
        let groups = MonthGroup.group([
            trip("2026-09-28", 3000),
            trip("2026-10-02", 4250),
            trip("2026-10-08", 1000),
            trip("2026-10-05", 500, "USD"),
        ], calendar: calendar)

        #expect(groups.count == 2)
        #expect(groups[0].trips.count == 3)
        #expect(groups[0].trips.first?.totalMinor == 1000, "newest trip first")
        #expect(groups[0].totals == [Money(amountMinor: 5250, currency: "EUR"), Money(amountMinor: 500, currency: "USD")])
        #expect(groups[1].totals == [Money(amountMinor: 3000, currency: "EUR")])
    }
}

// MARK: - INS-103: SwiftData → insight snapshots

@MainActor
struct InsightsSourceTests {
    @Test func mapsFinishedTripsPricesAndCategories() throws {
        let context = try makeContext()
        let now = Date()
        DemoData.seed(context, now: now)
        // An unfinished trip must not count.
        let store = SessionStore(context: context)
        store.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        store.addItem(code: milk, unitPriceMinor: 9_999, priceSource: .manual)

        let calculator = InsightsSource.calculator(context: context, now: now)
        #expect(calculator.hasEnoughData)
        #expect(calculator.currency == "EUR")
        // Trip totals in DemoData: 1154, 1570, 1407, 1952, 1955 → mean 1607.6 → 1608.
        #expect(calculator.averageTrip()?.amountMinor == 1608)
        #expect(calculator.limitAdherence().under == 5)
        #expect(calculator.categorySplit(in: DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now))
            .contains { $0.category == "en:sweet-spreads" })
        #expect(!calculator.priceChanges().isEmpty, "milk went from 0,89 to 0,99 at Lidl")
    }

    @Test func categoryTitles() {
        #expect(InsightsSource.categoryTitle("en:sweet-spreads") == "Sweet spreads")
        #expect(InsightsSource.categoryTitle("other") == "Other")
    }
}

// MARK: - INS-104: price-change badge

@MainActor
struct PriceTrendTests {
    @Test func risingPriceShowsBadgeNoHistoryDoesNot() throws {
        let context = try makeContext()
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        context.insert(lidl)
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let store = SessionStore(context: context, analytics: RecordingAnalytics(), now: { clock })
        store.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        store.addItem(code: milk, unitPriceMinor: 90, priceSource: .manual)
        #expect(PriceTrend.lookup(code: milk.value, store: lidl, context: context, now: clock) == nil, "one sighting is no trend")

        clock += 60 * 86_400
        store.addItem(code: milk, unitPriceMinor: 101, priceSource: .manual)
        store.addItem(code: bread, unitPriceMinor: 150, priceSource: .manual)
        let trend = try #require(PriceTrend.lookup(code: milk.value, store: lidl, context: context, now: clock))
        #expect(trend.roundedPercent == 12)
        #expect(PriceTrend.lookup(code: bread.value, store: lidl, context: context, now: clock) == nil)
        #expect(PriceTrend.lookup(code: milk.value, store: nil, context: context, now: clock) == nil)
    }
}
