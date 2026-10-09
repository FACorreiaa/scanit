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
