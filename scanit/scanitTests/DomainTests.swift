import Foundation
import ScanItCore
import SwiftData
import Testing
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
        #expect(item.priceSource == .manual, "a corrected price is a manual price")
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
