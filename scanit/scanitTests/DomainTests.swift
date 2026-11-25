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
        // SAVE-002: the tightest card, with a limit result and a saving, and a long store name.
        for (name, total, store) in [("saving", 4280, "Lidl"), ("saving-long", 123_456, "Continente Modelo Santa Maria da Feira")] {
            let sample = TripShareContent(
                storeName: store, date: Date(timeIntervalSince1970: 1_790_000_000),
                total: Money(amountMinor: total, currency: "EUR"), limit: Money(amountMinor: 6000, currency: "EUR"),
                itemCount: 23, saving: Money(amountMinor: 1234, currency: "EUR")
            )
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
        #expect(store.budget(for: "EUR") == nil)

        store.set(Money(amountMinor: 40_000, currency: "EUR"))
        #expect(BudgetStore(defaults: defaults).budget(for: "EUR") == Money(amountMinor: 40_000, currency: "EUR"))

        store.set(Money(amountMinor: 0, currency: "EUR"))
        #expect(store.budget(for: "EUR") == nil)
        #expect(BudgetStore(defaults: defaults).budget(for: "EUR") == nil)
    }

    /// BUD-001: a € budget and a $ budget live side by side, and removing one keeps the other.
    @Test func euroAndDollarBudgetsAreSeparate() throws {
        let defaults = try freshDefaults()
        let store = BudgetStore(defaults: defaults)
        store.set(Money(amountMinor: 40_000, currency: "EUR"))
        store.set(Money(amountMinor: 25_000, currency: "usd"))

        let relaunched = BudgetStore(defaults: defaults)
        #expect(relaunched.currencies == ["EUR", "USD"])
        #expect(relaunched.budget(for: "EUR") == Money(amountMinor: 40_000, currency: "EUR"))
        #expect(relaunched.budget(for: "USD") == Money(amountMinor: 25_000, currency: "USD"))
        #expect(relaunched.status(spent: Money(amountMinor: 24_000, currency: "USD"))?.state == .near)
        #expect(relaunched.status(spent: Money(amountMinor: 24_000, currency: "EUR"))?.state == .ok)

        relaunched.remove(currency: "EUR")
        #expect(BudgetStore(defaults: defaults).currencies == ["USD"])
    }

    /// BUD-001: the single ADD-003 budget survives the update and the old keys are gone.
    @Test func legacyBudgetIsMigrated() throws {
        let defaults = try freshDefaults()
        defaults.set(30_000, forKey: "monthlyBudget.minor")
        defaults.set("EUR", forKey: "monthlyBudget.currency")

        #expect(BudgetStore(defaults: defaults).budget(for: "EUR") == Money(amountMinor: 30_000, currency: "EUR"))
        #expect(defaults.object(forKey: "monthlyBudget.minor") == nil)
        #expect(defaults.object(forKey: "monthlyBudget.currency") == nil)
        #expect(BudgetStore(defaults: defaults).budget(for: "EUR") == Money(amountMinor: 30_000, currency: "EUR"),
                "still there on the launch after the migration")
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
        #expect(store.status(spent: Money(amountMinor: 100, currency: "GBP")) == nil, "no GBP budget, no status")
    }

    /// BUD-001: Insights measures each budget against its own currency's month.
    @Test func monthSpendIsPerCurrency() throws {
        let context = try makeContext()
        let now = Date()
        DemoData.seed(context, now: now)
        DemoData.seedForeignTrip(context, now: now)
        let euroMonth = InsightsSource.calculator(context: context, now: now).spend(.month).current

        let spends = InsightsSource.monthSpend(context: context, alsoIn: ["gbp"], now: now)
        #expect(spends.map(\.currency) == ["EUR", "GBP", "USD"])
        #expect(spends[0] == euroMonth, "the euro row matches the Insights month")
        #expect(spends[1].amountMinor == 0, "a budgeted currency with no trips shows 0")
        let usdTripThisMonth = Calendar.current.isDate(now.addingTimeInterval(-3 * 86_400), equalTo: now, toGranularity: .month)
        #expect(spends[2].amountMinor == (usdTripThisMonth ? DemoData.foreignTripTotalMinor : 0))
        #expect(InsightsSource.calculator(context: context, now: now).currency == "EUR",
                "the older dollar trip does not change the Insights currency")
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

// MARK: - MEAL-001: meals

@MainActor
struct MealBookTests {
    /// The backlog's check: 5 ingredients, 3 picked from past scans, still there after a relaunch.
    @Test func mealWithFiveIngredientsSurvivesARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "meals-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path() + suffix) }
        }
        do {
            let context = ModelContext(try ScanItSchema.container(url: url))
            DemoData.seed(context)
            let meal = MealBook.create(context: context)
            meal.name = "Pequeno-almoço"
            MealBook.setServings(4, of: meal)
            for typed in ["leite", "pão", "nutella"] {
                let suggestion = try #require(ShoppingList.suggestions(for: typed, context: context).first, "\(typed) was scanned before")
                MealBook.addIngredient(suggestion.name, code: suggestion.code, to: meal, context: context)
            }
            MealBook.addIngredient("Fruta da época", to: meal, context: context)
            MealBook.addIngredient("Mel", to: meal, context: context)
            MealBook.finishEditing(meal, context: context)
        }

        let reopened = ModelContext(try ScanItSchema.container(url: url))
        let meals = MealBook.meals(context: reopened)
        let meal = try #require(meals.first)
        #expect(meals.count == 1)
        #expect(meal.name == "Pequeno-almoço")
        #expect(meal.servings == 4)
        let ingredients = meal.liveIngredients
        #expect(ingredients.count == 5)
        #expect(ingredients.map(\.code).compactMap { $0 } == ["05601234567892", "04006381333931", "03017620422003"],
                "the 3 picked from past scans keep their barcode, in order")
        #expect(ingredients.suffix(2).map(\.text) == ["Fruta da época", "Mel"])

        let estimate = MealBook.estimate(meal, prices: InsightsSource.prices(context: reopened), currency: "EUR")
        #expect(estimate.pricedLines == 3, "every scanned ingredient has a price")
        #expect(estimate.unpricedLines == 2, "typed ones do not")
    }

    @Test func deletedMealIsHiddenButKeptForSync() throws {
        let context = try makeContext()
        let meal = MealBook.create(context: context)
        meal.name = "Sopa"
        MealBook.addIngredient("Cenouras", to: meal, context: context)
        MealBook.finishEditing(meal, context: context)
        #expect(MealBook.meals(context: context).count == 1)

        MealBook.delete(meal, context: context)
        #expect(MealBook.meals(context: context).isEmpty)
        let all = try context.fetch(FetchDescriptor<Meal>())
        #expect(all.count == 1 && all[0].deletedAt != nil, "soft delete keeps the row for sync")
        #expect(all[0].ingredients.allSatisfy { $0.deletedAt != nil }, "its ingredients go with it")
        #expect(all[0].syncStateRaw == SyncState.dirty.rawValue)
    }

    @Test func sameIngredientAddsAPackInsteadOfALine() throws {
        let context = try makeContext()
        let meal = MealBook.create(context: context)
        MealBook.addIngredient("Leite", code: milk.value, to: meal, context: context)
        MealBook.addIngredient("Leite meio gordo", code: milk.value, to: meal, context: context)
        MealBook.addIngredient("ovos", to: meal, context: context)
        MealBook.addIngredient("  Ovos ", to: meal, context: context)
        MealBook.addIngredient("   ", to: meal, context: context)

        let ingredients = meal.liveIngredients
        #expect(ingredients.map(\.text) == ["Leite", "ovos"])
        #expect(ingredients.map(\.quantity) == [2, 2])
    }

    @Test func emptyDraftIsDiscardedAndUnnamedMealIsNamed() throws {
        let context = try makeContext()
        let empty = MealBook.create(context: context)
        MealBook.finishEditing(empty, context: context)
        #expect(try context.fetch(FetchDescriptor<Meal>()).isEmpty, "an untouched new meal leaves nothing behind")

        let unnamed = MealBook.create(context: context)
        MealBook.addIngredient("Arroz", to: unnamed, context: context)
        MealBook.finishEditing(unnamed, context: context)
        #expect(unnamed.name == "Untitled meal")

        let spaced = MealBook.create(context: context)
        spaced.name = "  Bacalhau à Brás  "
        MealBook.finishEditing(spaced, context: context)
        #expect(spaced.name == "Bacalhau à Brás")
    }

    @Test func servingsAndPacksStayInRange() throws {
        let context = try makeContext()
        let meal = MealBook.create(context: context)
        MealBook.setServings(0, of: meal)
        #expect(meal.servings == 1)
        MealBook.setServings(99, of: meal)
        #expect(meal.servings == 12)
        let ingredient = try #require(MealBook.addIngredient("Massa", to: meal, context: context))
        MealBook.setQuantity(-3, of: ingredient)
        #expect(ingredient.quantity == 1)
        MealBook.setQuantity(50, of: ingredient)
        #expect(ingredient.quantity == 20)
    }

    /// The point of meals: they cost what the cheapest recent prices say.
    @Test func costUsesTheCheapestRecentPrice() throws {
        let context = try makeContext()
        let now = Date()
        DemoData.seed(context, now: now)
        let meal = MealBook.create(context: context)
        MealBook.setServings(2, of: meal)
        let ingredient = try #require(MealBook.addIngredient("Nutella", code: "03017620422003", to: meal, context: context))
        MealBook.setQuantity(2, of: ingredient)

        // DemoData Nutella: Lidl 4,09 (2 days ago), Continente 4,29 (6 days ago).
        let estimate = MealBook.estimate(meal, prices: InsightsSource.prices(context: context), currency: "EUR", now: now)
        #expect(estimate.lines.first?.price?.storeName == "Lidl")
        #expect(estimate.total == Money(amountMinor: 818, currency: "EUR"))
        #expect(estimate.perServing == Money(amountMinor: 409, currency: "EUR"))
        #expect(estimate.isComplete)
    }
}

// MARK: - MEAL-002: week plan

@MainActor
struct MealPlanTests {
    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private static func date(_ key: String, hour: Int = 12) -> Date {
        PlanWeek.date(for: key, calendar: calendar(firstWeekday: 2))!.addingTimeInterval(Double(hour - 12) * 3600)
    }

    private static func meal(_ name: String, in context: ModelContext) throws -> Meal {
        try #require(MealBook.meals(context: context).first { $0.name == name }, "\(name) is a demo meal")
    }

    @Test func weekStartsOnTheCalendarsFirstWeekday() {
        let monday = Self.calendar(firstWeekday: 2)
        let wednesday = Self.date("2026-11-18")
        #expect(PlanWeek(containing: wednesday, calendar: monday).days ==
                ["2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22"])
        #expect(PlanWeek(containing: wednesday, calendar: Self.calendar(firstWeekday: 1)).days.first == "2026-11-15",
                "a US calendar starts on Sunday")
        #expect(PlanWeek(containing: wednesday, calendar: monday).shifted(by: -1, calendar: monday).days.first == "2026-11-09")
        #expect(PlanWeek(containing: Self.date("2026-11-22", hour: 23), calendar: monday).days.first == "2026-11-16",
                "late on Sunday is still the same week")

        // Clocks go forward in Lisbon on 29 March 2026, and the year turns mid-week.
        let spring = PlanWeek(containing: Self.date("2026-03-29"), calendar: monday)
        #expect(spring.days.first == "2026-03-23" && spring.days.last == "2026-03-29")
        #expect(spring.shifted(by: 1, calendar: monday).days.first == "2026-03-30")
        #expect(PlanWeek(containing: Self.date("2026-12-31"), calendar: monday).days ==
                ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
    }

    /// The backlog's check: a 7-day plan with 10 meals is still there after a relaunch.
    @Test func aWeekOfTenMealsSurvivesARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "plan-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path() + suffix) }
        }
        let week = PlanWeek(containing: Self.date("2026-11-18"), calendar: Self.calendar(firstWeekday: 2))
        // (day index, slot, meal)
        let plan: [(Int, PlanSlot, String)] = [
            (0, .lunch, "Tosta mista"), (0, .dinner, "Arroz de pato"), (1, .dinner, "Pequeno-almoço"),
            (2, .lunch, "Tosta mista"), (2, .dinner, "Iogurte e café"), (3, .dinner, "Arroz de pato"),
            (4, .lunch, "Pequeno-almoço"), (5, .dinner, "Tosta mista"), (6, .lunch, "Iogurte e café"),
            (6, .dinner, "Arroz de pato"),
        ]
        do {
            let context = ModelContext(try ScanItSchema.container(url: url))
            DemoData.seed(context)
            DemoData.seedMeals(context)
            for (day, slot, name) in plan {
                MealPlan.plan(try Self.meal(name, in: context), day: week.days[day], slot: slot, context: context)
            }
            let sunday = try #require(MealPlan.entries(in: week, context: context).last)
            MealPlan.setServings(6, of: sunday)
            try context.save()
        }

        let reopened = ModelContext(try ScanItSchema.container(url: url))
        let entries = MealPlan.entries(in: week, context: reopened)
        #expect(entries.count == 10)
        #expect(Set(entries.map(\.day)).count == 7, "every day has a meal")
        let saved = Set(entries.map { "\($0.day) \($0.slotRaw) \($0.meal?.name ?? "")" })
        #expect(saved == Set(plan.map { "\(week.days[$0.0]) \($0.1.rawValue) \($0.2)" }))
        #expect(entries.first { $0.day == week.days[6] && $0.slot == .dinner }?.servings == 6)
        #expect(entries.first { $0.day == week.days[0] && $0.slot == .lunch }?.servings == 2, "starts at the meal's own servings")
    }

    @Test func planningAFilledSlotReplacesItsMeal() throws {
        let context = try makeContext()
        DemoData.seedMeals(context)
        let day = "2026-11-18"
        let first = MealPlan.plan(try Self.meal("Tosta mista", in: context), day: day, slot: .lunch, context: context)
        MealPlan.setServings(5, of: first)
        let second = MealPlan.plan(try Self.meal("Arroz de pato", in: context), day: day, slot: .lunch, context: context)

        #expect(first.id == second.id, "one meal per slot")
        #expect(second.meal?.name == "Arroz de pato")
        #expect(second.servings == 4, "the new meal's own servings")
        #expect(try context.fetch(FetchDescriptor<PlanEntry>()).count == 1)
        MealPlan.plan(try Self.meal("Tosta mista", in: context), day: day, slot: .dinner, context: context)
        #expect(MealPlan.entries(in: PlanWeek(containing: Self.date(day), calendar: Self.calendar(firstWeekday: 2)),
                                 context: context).count == 2, "lunch and dinner are separate slots")
    }

    @Test func copyLastWeekFillsOnlyTheEmptySlots() throws {
        let context = try makeContext()
        DemoData.seedMeals(context)
        let monday = Self.calendar(firstWeekday: 2)
        let thisWeek = PlanWeek(containing: Self.date("2026-11-18"), calendar: monday)
        let lastWeek = thisWeek.shifted(by: -1, calendar: monday)
        let tosta = try Self.meal("Tosta mista", in: context)
        let arroz = try Self.meal("Arroz de pato", in: context)

        let copied = MealPlan.plan(tosta, day: lastWeek.days[0], slot: .lunch, context: context)
        MealPlan.setServings(3, of: copied)
        MealPlan.plan(arroz, day: lastWeek.days[0], slot: .dinner, context: context)
        MealPlan.plan(tosta, day: lastWeek.days[4], slot: .dinner, context: context)
        // Already planned this week: Monday dinner stays as it is.
        MealPlan.plan(tosta, day: thisWeek.days[0], slot: .dinner, context: context)

        #expect(MealPlan.copyable(from: lastWeek, to: thisWeek, context: context).count == 2)
        #expect(MealPlan.copy(from: lastWeek, to: thisWeek, context: context) == 2)
        let entries = MealPlan.entries(in: thisWeek, context: context)
        #expect(entries.count == 3)
        let mondayLunch = entries.first { $0.day == thisWeek.days[0] && $0.slot == .lunch }
        #expect(mondayLunch?.meal?.name == "Tosta mista" && mondayLunch?.servings == 3, "same weekday, slot and servings")
        #expect(entries.first { $0.day == thisWeek.days[0] && $0.slot == .dinner }?.meal?.name == "Tosta mista",
                "a slot already planned is not overwritten")
        #expect(entries.first { $0.day == thisWeek.days[4] && $0.slot == .dinner }?.meal?.name == "Tosta mista")
        #expect(MealPlan.entries(in: lastWeek, context: context).count == 3, "last week is left as it was")
        #expect(MealPlan.copy(from: lastWeek, to: thisWeek, context: context) == 0, "copying twice adds nothing")
    }

    @Test func aDeletedMealLeavesThePlan() throws {
        let context = try makeContext()
        DemoData.seedMeals(context)
        let week = PlanWeek(containing: Self.date("2026-11-18"), calendar: Self.calendar(firstWeekday: 2))
        let arroz = try Self.meal("Arroz de pato", in: context)
        MealPlan.plan(arroz, day: week.days[1], slot: .dinner, context: context)
        MealPlan.plan(try Self.meal("Tosta mista", in: context), day: week.days[2], slot: .lunch, context: context)

        MealBook.delete(arroz, context: context)
        let entries = MealPlan.entries(in: week, context: context)
        #expect(entries.map { $0.meal?.name } == ["Tosta mista"])
        let all = try context.fetch(FetchDescriptor<PlanEntry>())
        #expect(all.count == 2 && all.contains { $0.deletedAt != nil }, "soft deleted, kept for sync")
        #expect(MealPlan.copy(from: week, to: week.shifted(by: 1), context: context) == 1, "a deleted meal is not copied")
    }

    /// The week's cost: each planned meal scaled to its servings, at the cheapest recent prices.
    @Test func weekCostAddsUpThePlannedMeals() throws {
        let context = try makeContext()
        let now = Date()
        DemoData.seed(context, now: now)
        DemoData.seedMeals(context, now: now)
        let week = PlanWeek(containing: now)
        let breakfast = MealPlan.plan(try Self.meal("Pequeno-almoço", in: context), day: week.days[0], slot: .lunch, context: context)
        MealPlan.setServings(3, of: breakfast)
        MealPlan.plan(try Self.meal("Tosta mista", in: context), day: week.days[1], slot: .lunch, context: context)
        MealPlan.plan(try Self.meal("Arroz de pato", in: context), day: week.days[1], slot: .dinner, context: context)

        let prices = InsightsSource.prices(context: context)
        let planned = MealPlan.entries(in: week, context: context).map { entry in
            MealPlan.planned(entry, estimate: MealBook.estimate(entry.meal!, prices: prices, currency: "EUR", now: now))
        }
        // Pequeno-almoço serves 2: milk 0,99 + bread 1,39 + Nutella 4,09 = 6,47 (all Lidl, 2 days
        // ago); for 3 that is 6,47 × 3 ÷ 2 = 9,705, so 9,71. Tosta mista: bread 1,39, plus two
        // typed ingredients. Arroz de pato: all typed, no price.
        #expect(planned.map { $0.cost?.amountMinor } == [971, 139, nil])
        let summary = PlanCost.summary(planned, currency: "EUR")
        #expect(summary.total == Money(amountMinor: 1_110, currency: "EUR"))
        #expect(summary.meals == 3 && summary.pricedMeals == 2 && summary.completeMeals == 1)
        #expect(!summary.isComplete, "the week costs at least this")
    }
}

// MARK: - MEAL-003: plan to shopping list

@MainActor
struct PlanToListTests {
    private let week = PlanWeek(containing: Date(timeIntervalSince1970: 1_794_960_000)) // 2026-11-18

    private func plannedContext() throws -> ModelContext {
        let context = try makeContext()
        DemoData.seedMeals(context)
        let meals = MealBook.meals(context: context)
        let breakfast = try #require(meals.first { $0.name == "Pequeno-almoço" })
        let tosta = try #require(meals.first { $0.name == "Tosta mista" })
        // Both take one pack of bread for 2; planned for 2 and for 4: 1 + 2 = 3 packs.
        MealPlan.plan(breakfast, day: week.days[0], slot: .lunch, context: context)
        let dinner = MealPlan.plan(tosta, day: week.days[1], slot: .dinner, context: context)
        MealPlan.setServings(4, of: dinner)
        try context.save()
        return context
    }

    /// The backlog's check: two meals that share an ingredient give one list line with both
    /// amounts, and scanning the product still ticks it.
    @Test func sharedIngredientIsOneLineAndAScanTicksIt() throws {
        let context = try plannedContext()
        let lines = MealPlan.listLines(in: week, context: context)
        #expect(lines.map(\.text) == ["Leite meio gordo", "Pão de forma", "Nutella", "Queijo", "Fiambre"])
        let bread = try #require(lines.first { $0.code == "04006381333931" })
        #expect(bread.packs == 3)
        #expect(bread.meals == ["Pequeno-almoço", "Tosta mista"])
        #expect(lines.first { $0.text == "Queijo" }?.packs == 2, "1 for 2, planned for 4")

        #expect(MealPlan.addToList(lines, atHome: [], context: context) == 5)
        let list = ShoppingList.lines(context: context)
        #expect(list.count == 5)
        let breadLine = try #require(list.first { $0.code == "04006381333931" })
        #expect(breadLine.quantity == 3, "one line, combined")

        let session = SessionStore(context: context, analytics: RecordingAnalytics())
        session.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        session.addItem(code: ScannedCode(kind: .gtin, value: "04006381333931"), productName: "Pão de forma",
                        unitPriceMinor: 139, priceSource: .manual)
        #expect(breadLine.isDone, "the scan ticks it")
        #expect(list.filter(\.isDone).count == 1)
    }

    @Test func whatIsAtHomeStaysOffAndIsRemembered() throws {
        let context = try plannedContext()
        let cheese = PlanList.key(text: "Queijo", code: nil)
        let lines = MealPlan.listLines(in: week, context: context)
        #expect(MealPlan.addToList(lines, atHome: [cheese], context: context) == 4)
        #expect(!ShoppingList.lines(context: context).contains { $0.text == "Queijo" })

        let tosta = try #require(MealBook.meals(context: context).first { $0.name == "Tosta mista" })
        #expect(tosta.liveIngredients.first { $0.text == "Queijo" }?.inPantry == true, "remembered on the meal")
        #expect(MealPlan.listLines(in: week, context: context).first { $0.key == cheese }?.inPantry == true,
                "next time it starts unticked")

        // Out of cheese again: ticking it back puts it on the list and forgets the pantry mark.
        MealPlan.addToList(MealPlan.listLines(in: week, context: context), atHome: [], context: context)
        #expect(ShoppingList.lines(context: context).contains { $0.text == "Queijo" })
        #expect(tosta.liveIngredients.first { $0.text == "Queijo" }?.inPantry == false)
    }

    @Test func addingTheWeekTwiceDoesNotDoubleIt() throws {
        let context = try plannedContext()
        // Already on the list, typed by hand: the plan raises it instead of adding a second line.
        ShoppingList.add("pão de forma", context: context)
        let lines = MealPlan.listLines(in: week, context: context)
        MealPlan.addToList(lines, atHome: [], context: context)
        MealPlan.addToList(lines, atHome: [], context: context)

        let list = ShoppingList.lines(context: context)
        #expect(list.count == 5)
        #expect(list.filter { $0.text.lowercased().hasPrefix("pão") }.map(\.quantity) == [3])
        let packs: [Int] = list.map(\.quantity)
        #expect(packs.reduce(0, +) == 9, "milk 1, bread 3, Nutella 1, cheese 2, ham 2")
    }

    @Test func mergeNeverLowersAQuantity() throws {
        let context = try makeContext()
        let line = try #require(ShoppingList.merge("Ovos", code: nil, quantity: 4, context: context))
        ShoppingList.merge("ovos", code: nil, quantity: 2, context: context)
        #expect(line.quantity == 4)
        #expect(ShoppingList.merge("  ", code: nil, quantity: 2, context: context) == nil)
        #expect(ListItem(text: "Sal").quantity == 1, "lines from before MEAL-003 ask for one")
    }
}

// MARK: - MEAL-004: the list's cost per store

@MainActor
struct ListEstimateTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func demo() throws -> ModelContext {
        let context = try makeContext()
        DemoData.seed(context, now: now)
        DemoData.seedList(context, now: now)
        return context
    }

    private func store(_ name: String, in context: ModelContext) throws -> Store {
        try #require(try context.fetch(FetchDescriptor<Store>()).first { $0.name == name })
    }

    /// Worked by hand in `DemoData.seedList`: each store's latest price × packs, summed.
    @Test func demoListCostsAtBothStores() throws {
        let context = try demo()
        let estimate = ListEstimate.estimate(context: context, now: now)
        #expect(estimate.stores.map(\.storeName) == ["Lidl", "Continente"])
        #expect(estimate.stores.map(\.total.amountMinor) == [2 * 99 + 409 + 519, 2 * 99 + 429 + 549])
        #expect(estimate.stores.allSatisfy { $0.missingLines == 0 })
        #expect(estimate.unpricedLines == 1, "Queijo is typed")

        // The limit is the estimate rounded up to a whole euro, and follows the chosen store.
        let prefill = try #require(TripPrefill(estimate))
        let lidl = try store("Lidl", in: context)
        let continente = try store("Continente", in: context)
        #expect(prefill.storeID == lidl.id)
        #expect(prefill.limit(for: lidl.id) == Money(amountMinor: 1200, currency: "EUR"))
        #expect(prefill.limit(for: continente.id) == Money(amountMinor: 1200, currency: "EUR"))
        #expect(prefill.limit(for: nil) == nil)
    }

    @Test func tickedLinesAndRemovedStoresAreLeftOut() throws {
        let context = try demo()
        let coffee = try #require(ShoppingList.lines(context: context).first { $0.text == "Café moído" })
        ShoppingList.toggle(coffee, context: context, now: now)
        let lidl = try store("Lidl", in: context)
        lidl.deletedAt = now
        try context.save()

        let estimate = ListEstimate.estimate(context: context, now: now)
        #expect(estimate.stores.map(\.storeName) == ["Continente"])
        #expect(estimate.stores.first?.total.amountMinor == 2 * 99 + 429)
    }

    @Test func estimateChipComesFirstAndReplacesTheSameAmount() throws {
        let context = try demo()
        let options = TripStartOptions(context: context, now: now)
        let history = options.limitSuggestions(currency: "EUR")
        let estimate = Money(amountMinor: 1200, currency: "EUR")
        let chips = options.limitSuggestions(currency: "EUR", estimate: estimate)
        #expect(chips.first == .init(kind: .estimate, amount: estimate))
        #expect(chips.dropFirst() == history.filter { $0.amount != estimate }[...])
        #expect(options.limitSuggestions(currency: "USD", estimate: estimate).allSatisfy { $0.kind != .estimate })
        #expect(TripStartOptions.roundedUp(Money(amountMinor: 1126, currency: "EUR")).amountMinor == 1200)
        #expect(TripStartOptions.roundedUp(Money(amountMinor: 1200, currency: "EUR")).amountMinor == 1200)
    }

    /// The cheapest store is offered even when it is not among the 8 most recent.
    @Test func cheapestStoreOutsideTheRecentOnesIsStillOffered() throws {
        let context = try makeContext()
        let old = Store(name: "Old shop", countryCode: "PT", currency: "EUR", now: now.addingTimeInterval(-86_400 * 30))
        context.insert(old)
        for index in 0..<TripStartOptions.maxRecentStores {
            context.insert(Store(name: "Shop \(index)", countryCode: "PT", currency: "EUR", now: now.addingTimeInterval(Double(index))))
        }
        try context.save()

        #expect(!TripStartOptions(context: context, now: now).recentStores.contains { $0.id == old.id })
        let including = TripStartOptions(context: context, now: now, including: old.id)
        #expect(including.recentStores.first?.id == old.id)
    }
}

// MARK: - MEAL-005: planned vs actual

@MainActor
struct TripPlanTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func demo() throws -> (ModelContext, TripPrefill, Store) {
        let context = try makeContext()
        DemoData.seed(context, now: now)
        DemoData.seedList(context, now: now)
        let estimate = ListEstimate.estimate(context: context, now: now)
        let prefill = try #require(TripPrefill(estimate, lines: ShoppingList.lines(context: context)))
        let lidl = try #require(try context.fetch(FetchDescriptor<Store>()).first { $0.name == "Lidl" })
        return (context, prefill, lidl)
    }

    /// The Done-when: a planned trip with one extra item. Lidl's estimate is €11,26 (MEAL-004) and
    /// leaves out the typed "Queijo". Bought: milk 2 × 0,99, Nutella 4,09, coffee 5,19, a cheese
    /// that answers "Queijo" at 2,50, and bread at 1,49 that was not on the list.
    /// Spent 1,98 + 4,09 + 5,19 + 2,50 + 1,49 = €15,25, so €3,99 over the plan.
    @Test func plannedTripShowsTheExtraItemAndTheDifference() throws {
        let (context, prefill, lidl) = try demo()
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
        let trip = sessions.startTrip(
            store: lidl, limitMinor: 1200, currency: "EUR", plan: prefill.plan(for: lidl.id, currency: "EUR")
        )
        sessions.addItem(code: milk, productName: "Leite meio gordo", quantity: 2, unitPriceMinor: 99, priceSource: .manual)
        sessions.addItem(code: ScannedCode(kind: .gtin, value: "03017620422003"), productName: "Nutella", unitPriceMinor: 409, priceSource: .manual)
        sessions.addItem(code: ScannedCode(kind: .gtin, value: "05601111111116"), unitPriceMinor: 519, priceSource: .manual)
        sessions.addItem(code: ScannedCode(kind: .gtin, value: "05609999999990"), productName: "Queijo flamengo fatias", unitPriceMinor: 250, priceSource: .manual)
        sessions.addItem(code: bread, productName: "Pão de forma", unitPriceMinor: 149, priceSource: .manual)
        // The list is ticked and cleared while you shop; the plan is not.
        ShoppingList.clearDone(context: context)

        let summary = try #require(TripPlanSummary(session: trip))
        #expect(summary.planned == Money(amountMinor: 1126, currency: "EUR"), "the plain estimate, not the €12 limit")
        #expect(summary.spent.amountMinor == 1525)
        #expect(summary.difference == Money(amountMinor: 399, currency: "EUR"))
        #expect(summary.differenceText == "You spent \(Money(amountMinor: 399, currency: "EUR").formatted()) more than planned")
        #expect(summary.extras.map(\.code) == [bread.value])
        #expect(summary.extrasTotal.amountMinor == 149)
        #expect(summary.unpricedLines == 1, "Queijo")
    }

    /// A store with no estimate, or another currency, has no planned cost; the extras still show.
    @Test func noPlannedCostWithoutAnEstimateAtThatStore() throws {
        let (context, prefill, lidl) = try demo()
        let corner = Store(name: "Corner shop", countryCode: "PT", currency: "EUR")
        context.insert(corner)
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())

        let trip = sessions.startTrip(store: corner, limitMinor: nil, currency: "EUR", plan: prefill.plan(for: corner.id, currency: "EUR"))
        sessions.addItem(code: bread, productName: "Pão de forma", unitPriceMinor: 149, priceSource: .manual)
        let summary = try #require(TripPlanSummary(session: trip))
        #expect(summary.planned == nil)
        #expect(summary.difference == nil)
        #expect(summary.differenceText == nil)
        #expect(summary.unpricedLines == 4)
        #expect(summary.extras.map(\.code) == [bread.value])

        #expect(prefill.plan(for: lidl.id, currency: "USD").cost == nil)
        #expect(prefill.plan(for: nil, currency: "EUR").cost == nil, "a new store")
    }

    /// The plan is read back from disk for a past trip in History. A list of typed lines only
    /// stores no codes: an empty list, which must come back as one, not as "no plan".
    @Test func planSurvivesARelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "plan-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path() + suffix) }
        }
        var tripIDs: [UUID] = []
        do {
            let context = ModelContext(try ScanItSchema.container(url: url))
            DemoData.seed(context, now: now)
            DemoData.seedList(context, now: now)
            let estimate = ListEstimate.estimate(context: context, now: now)
            let prefill = try #require(TripPrefill(estimate, lines: ShoppingList.lines(context: context)))
            let lidl = try #require(try context.fetch(FetchDescriptor<Store>()).first { $0.name == "Lidl" })
            let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
            let planned = sessions.startTrip(store: lidl, limitMinor: nil, currency: "EUR", plan: prefill.plan(for: lidl.id, currency: "EUR"))
            sessions.addItem(code: bread, productName: "Pão de forma", unitPriceMinor: 149, priceSource: .manual)
            tripIDs.append(planned.id)

            let typedOnly = TripPlan(lines: [PlannedLine(text: "Queijo", code: nil)], cost: nil, unpricedLines: 1)
            let typed = sessions.startTrip(store: lidl, limitMinor: nil, currency: "EUR", plan: typedOnly)
            sessions.addItem(code: bread, productName: "Pão de forma", unitPriceMinor: 149, priceSource: .manual)
            tripIDs.append(typed.id)
            try context.save()
        }

        let reopened = ModelContext(try ScanItSchema.container(url: url))
        let trips = try reopened.fetch(FetchDescriptor<ShoppingSession>())
        let planned = try #require(trips.first { $0.id == tripIDs[0] })
        let summary = try #require(TripPlanSummary(session: planned))
        #expect(summary.planned == Money(amountMinor: 1126, currency: "EUR"))
        #expect(summary.unpricedLines == 1)
        #expect(summary.extras.map(\.code) == [bread.value])
        #expect(planned.plannedCodes?.count == 3)

        let typed = try #require(trips.first { $0.id == tripIDs[1] })
        #expect(typed.plannedCodes == [], "no codes is still a plan")
        let typedSummary = try #require(TripPlanSummary(session: typed))
        #expect(typedSummary.planned == nil)
        #expect(typedSummary.extras.map(\.code) == [bread.value])
    }

    /// Trips started any other way, and trips from before MEAL-005, have no plan.
    @Test func tripWithoutAPlanHasNoSummary() throws {
        let (context, _, lidl) = try demo()
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics())
        let trip = sessions.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        sessions.addItem(code: bread, productName: "Pão de forma", unitPriceMinor: 149, priceSource: .manual)
        #expect(TripPlanSummary(session: trip) == nil)
    }
}

// MARK: - SAVE-003: savings on Insights

@MainActor
struct MonthSavingSummaryTests {
    /// 2026-09-21 19:33 UTC: demo trips 2, 6, 13 and 20 days ago fall in September, 27 days ago in
    /// August.
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func euro(_ minor: Int) -> String { Money(amountMinor: minor, currency: "EUR").formatted() }

    /// Worked by hand from `DemoData.seed`, using the trip savings in `TripSavingSummaryTests`:
    /// +60, −146 and +90, plus 20 days ago at Continente vs Lidl 27 days ago: milk −10 × 4,
    /// Nutella −30, yogurt −4 × 4, coffee unpriced = −86, all of it cheaper at Lidl.
    @Test func demoMonthAndTrend() throws {
        let context = try makeContext()
        DemoData.seed(context, now: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let calculator = InsightsSource.calculator(context: context, now: now, calendar: calendar)
        let trend = calculator.monthlySavings()

        #expect(trend.count == 6)
        let september = try #require(trend.last).saving
        #expect(september.saving.amountMinor == 60 - 146 + 90 - 86)
        #expect(september.comparedTrips == 4)
        // INS-13 per store: 146 (6 days ago) + 86 (20 days ago), both at Lidl.
        #expect(september.missedByStore.map(\.storeName) == ["Lidl"])
        #expect(september.missedByStore.map(\.missed.amountMinor) == [232])

        // August: only the first trip, with nothing to compare it to. A trip, not a comparison.
        let august = trend[4].saving
        #expect(august.trips == 1)
        #expect(!august.hasComparison)
        #expect(trend.prefix(4).allSatisfy { $0.saving.trips == 0 })

        let summary = MonthSavingSummary(september, comparedBefore: false)
        #expect(summary.title == "Paid more this month")
        #expect(summary.value == euro(82))
        #expect(summary.detail == "Than other stores · 4 trips")
    }

    @Test func wording() {
        func month(_ minor: Int, compared: Int) -> PeriodSaving {
            PeriodSaving(
                saving: Money(amountMinor: minor, currency: "EUR"), missed: Money(amountMinor: 0, currency: "EUR"),
                trips: max(compared, 1), comparedTrips: compared, missedByStore: []
            )
        }
        let saved = MonthSavingSummary(month(60, compared: 1), comparedBefore: false)
        #expect(saved.title == "Saved this month")
        #expect(saved.value == euro(60))
        #expect(saved.detail == "Vs other stores · 1 trip")

        let even = MonthSavingSummary(month(0, compared: 2), comparedBefore: false)
        #expect(even.value == euro(0))
        #expect(even.detail == "Same as other stores · 2 trips")

        // A month with trips but nothing to compare is not "saved €0".
        let nothing = MonthSavingSummary(month(0, compared: 0), comparedBefore: true)
        #expect(nothing.value == "—")
        #expect(nothing.detail == "Nothing compared yet this month")
        #expect(MonthSavingSummary(month(0, compared: 0), comparedBefore: false).detail == "Needs prices from a second store")
    }
}

// MARK: - SAVE-002: saving on the finish sheet and in History

@MainActor
struct TripSavingSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func demoSavings() throws -> (savings: [UUID: TripSavingSummary], trips: [Int: ShoppingSession]) {
        let context = try makeContext()
        DemoData.seed(context, now: now)
        let sessions = try context.fetch(FetchDescriptor<ShoppingSession>())
        let byDaysAgo = Dictionary(uniqueKeysWithValues: sessions.map {
            (Int((now.timeIntervalSince($0.startedAt) / 86_400).rounded()), $0)
        })
        return (InsightsSource.tripSavings(sessions, context: context), byDaysAgo)
    }

    /// Worked by hand from `DemoData.seed`: each trip against the other store's latest prices
    /// before it ended.
    @Test func demoTripsShowWorkedOutSavings() throws {
        let (savings, trips) = try demoSavings()
        let euro = { (minor: Int) in Money(amountMinor: minor, currency: "EUR").formatted() }

        // 2 days ago at Lidl vs Continente 6 days ago (yogurt 20 days ago): bread +10, Nutella +20,
        // coffee +30, milk and yogurt 0. Nothing was cheaper at Continente.
        let lidl = try #require(trips[2].flatMap { savings[$0.id] })
        #expect(lidl.saving.amountMinor == 60)
        #expect(lidl.text == "Saved \(euro(60)) vs other stores")
        #expect(lidl.missedText == nil)
        #expect(lidl.coverageText == nil)

        // 6 days ago at Continente vs Lidl 13 days ago (Nutella 27 days ago): milk −4 × 4, Nutella
        // −30 × 2, bread −20, coffee −50. All of it was cheaper at Lidl.
        let continente = try #require(trips[6].flatMap { savings[$0.id] })
        #expect(continente.saving.amountMinor == -146)
        #expect(continente.text == "\(euro(146)) more than other stores")
        #expect(continente.shortText == "\(euro(146)) more than elsewhere")
        #expect(continente.missedText == "Could have saved \(euro(146)) at Lidl")

        // 13 days ago at Lidl vs Continente 20 days ago: milk +4 × 4, coffee +50, yogurt +4 × 6;
        // Continente had no bread price yet.
        let partial = try #require(trips[13].flatMap { savings[$0.id] })
        #expect(partial.saving.amountMinor == 90)
        #expect(partial.coverageText == "Compared on 3 of 4 products")

        // 27 days ago: the first trip, so no other store had prices yet.
        let first = try #require(trips[27])
        #expect(savings[first.id] == nil)
    }

    @Test func sameAsElsewhereAndUnnamedStore() {
        let euro = { (minor: Int) in Money(amountMinor: minor, currency: "EUR") }
        let summary = TripSavingSummary(saving: euro(0), missed: euro(40), missedAt: nil, compared: 2, products: 2)
        #expect(summary.text == "Same as other stores")
        #expect(summary.shortText == "Same as elsewhere")
        #expect(summary.missedText == "Could have saved \(euro(40).formatted()) elsewhere")
        #expect(summary.coverageText == nil)
        #expect(!summary.isSaving)
    }

    @Test func shareCardCarriesOnlyARealSaving() {
        func card(_ saving: Int?) -> TripShareContent {
            TripShareContent(
                storeName: "Lidl", date: now, total: Money(amountMinor: 4280, currency: "EUR"), limit: nil,
                itemCount: 3, saving: saving.map { Money(amountMinor: $0, currency: "EUR") }
            )
        }
        #expect(card(60).savingLine == "Saved \(Money(amountMinor: 60, currency: "EUR").formatted()) vs other stores")
        #expect(card(-146).savingLine == nil, "an overspend is not a saving to share")
        #expect(card(0).savingLine == nil)
        #expect(card(nil).savingLine == nil)
        #expect(TripShareContent.footer(includesSaving: true).contains("saving"))
        #expect(!TripShareContent.footer(includesSaving: false).contains("saving"))
    }

    /// Missed savings at two stores: the line names the top store with its own amount, not the
    /// trip's total. Lidl is 30 cheaper on milk, Continente 10 cheaper on bread.
    @Test func missedLineNamesTheTopStoreWithItsOwnAmount() throws {
        let context = try makeContext()
        let pingo = Store(name: "Pingo Doce", countryCode: "PT", currency: "EUR")
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        let continente = Store(name: "Continente", countryCode: "PT", currency: "EUR")
        [pingo, lidl, continente].forEach(context.insert)
        let bread = ScannedCode(kind: .gtin, value: "04006381333931")
        for (store, code, minor) in [(lidl, milk.value, 70), (continente, milk.value, 110), (lidl, bread.value, 120), (continente, bread.value, 90)] {
            context.insert(PriceObservation(
                store: store, code: code, price: Money(amountMinor: minor, currency: "EUR"), source: .manual,
                now: now.addingTimeInterval(-86_400)
            ))
        }
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics(), now: { [now] in now })
        sessions.startTrip(store: pingo, limitMinor: nil, currency: "EUR")
        sessions.addItem(code: milk, unitPriceMinor: 100, priceSource: .manual)
        sessions.addItem(code: bread, unitPriceMinor: 100, priceSource: .manual)
        let trip = try #require(sessions.finishTrip())

        let saving = try #require(InsightsSource.tripSavings([trip], context: context)[trip.id])
        #expect(saving.missed.amountMinor == 30, "Lidl's own 30, not the trip's 40")
        #expect(saving.missedText == "Could have saved \(Money(amountMinor: 30, currency: "EUR").formatted()) at Lidl")
    }

    /// The newest trip is in euros, so a calculator built from the home currency would drop this one.
    @Test func dollarTripIsMeasuredInDollars() throws {
        let context = try makeContext()
        let market = Store(name: "Market", countryCode: "US", currency: "USD")
        let other = Store(name: "Other", countryCode: "US", currency: "USD")
        let lidl = Store(name: "Lidl", countryCode: "PT", currency: "EUR")
        let continente = Store(name: "Continente", countryCode: "PT", currency: "EUR")
        [market, other, lidl, continente].forEach(context.insert)
        let gallon = "00070038000563"
        context.insert(PriceObservation(
            store: other, code: gallon, price: Money(amountMinor: 399, currency: "USD"), source: .manual,
            now: now.addingTimeInterval(-86_400)
        ))
        context.insert(PriceObservation(
            store: continente, code: gallon, price: Money(amountMinor: 999, currency: "EUR"), source: .manual,
            now: now.addingTimeInterval(-86_400)
        ))
        var clock = now
        let sessions = SessionStore(context: context, analytics: RecordingAnalytics(), now: { clock })
        sessions.startTrip(store: market, limitMinor: nil, currency: "USD")
        sessions.addItem(code: ScannedCode(kind: .gtin, value: gallon), productName: nil, quantity: 2, unitPriceMinor: 349, priceSource: .manual)
        let trip = try #require(sessions.finishTrip())
        clock = now.addingTimeInterval(3_600)
        sessions.startTrip(store: lidl, limitMinor: nil, currency: "EUR")
        sessions.addItem(code: ScannedCode(kind: .gtin, value: gallon), productName: nil, quantity: 1, unitPriceMinor: 899, priceSource: .manual)
        let euroTrip = try #require(sessions.finishTrip())
        #expect(InsightsSource.homeCurrency(context: context) == "EUR")

        let savings = InsightsSource.tripSavings([trip, euroTrip], context: context)
        #expect(savings[trip.id]?.saving == Money(amountMinor: 100, currency: "USD"))
        #expect(savings[euroTrip.id]?.saving == Money(amountMinor: 100, currency: "EUR"))
    }
}
