import Foundation
import Testing
@testable import ScanItCore

/// `Fixtures/insights.json`: hand-computed expectations, shared with Android.
private struct InsightsFixture: Decodable {
    struct Expected: Decodable {
        struct Period: Decodable { let currentMinor, previousMinor, deltaMinor: Int; let deltaPercent: Double }
        struct Adherence: Decodable { let under, withLimit: Int }
        struct Store: Decodable { let storeId: String; let totalMinor: Int }
        struct ProductRow: Decodable { let code: String; let totalMinor, quantity: Int }
        struct Change: Decodable { let storeId, code: String; let firstMinor, latestMinor: Int; let percent: Double }
        struct Cheapest: Decodable { let code, cheapestStoreId: String; let cheapestMinor, savingMinor: Int }
        struct Category: Decodable { let category: String; let totalMinor: Int }

        let ins01_week: Period
        let ins01_month: Period
        let ins02_averageTripMinor: Int
        let ins03: Adherence
        let ins04_month: [Store]
        let ins05_month: [ProductRow]
        let ins06: [Change]
        let ins07: [Cheapest]
        let ins08_month: [Category]
    }

    let now: Date
    let currency: String
    let trips: [TripSnapshot]
    let prices: [PriceSnapshot]
    let expected: Expected
}

@Suite("Insights (INS-01…08)")
struct InsightsTests {
    private let fixture: InsightsFixture
    private let calculator: InsightsCalculator

    init() throws {
        fixture = try WireCoding.decoder().decode(InsightsFixture.self, from: Fixtures.data("insights.json"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        calculator = InsightsCalculator(
            trips: fixture.trips, prices: fixture.prices, currency: fixture.currency, now: fixture.now, calendar: calendar
        )
    }

    private func check(_ spend: PeriodSpend, _ expected: InsightsFixture.Expected.Period) {
        #expect(spend.current.amountMinor == expected.currentMinor)
        #expect(spend.previous.amountMinor == expected.previousMinor)
        #expect(spend.delta.amountMinor == expected.deltaMinor)
        #expect(abs((spend.deltaPercent ?? .nan) - expected.deltaPercent) < 0.001)
    }

    @Test func ins01SpendThisWeekAndMonth() {
        check(calculator.spend(.week), fixture.expected.ins01_week)
        check(calculator.spend(.month), fixture.expected.ins01_month)
    }

    @Test func ins02AverageTrip() {
        #expect(calculator.averageTrip()?.amountMinor == fixture.expected.ins02_averageTripMinor)
    }

    @Test func ins03TripsUnderLimit() {
        let adherence = calculator.limitAdherence()
        #expect(adherence.under == fixture.expected.ins03.under)
        #expect(adherence.withLimit == fixture.expected.ins03.withLimit)
    }

    @Test func ins04SpendByStore() {
        let rows = calculator.spendByStore(in: calculator.interval(.month))
        #expect(rows.map(\.storeId) == fixture.expected.ins04_month.map(\.storeId))
        #expect(rows.map(\.total.amountMinor) == fixture.expected.ins04_month.map(\.totalMinor))
    }

    @Test func ins05TopProducts() {
        let rows = calculator.topProducts(in: calculator.interval(.month))
        #expect(rows.map(\.code) == fixture.expected.ins05_month.map(\.code))
        #expect(rows.map(\.total.amountMinor) == fixture.expected.ins05_month.map(\.totalMinor))
        #expect(rows.map(\.quantity) == fixture.expected.ins05_month.map(\.quantity))
    }

    @Test func ins06PriceChanges() {
        let rows = calculator.priceChanges()
        #expect(rows.count == fixture.expected.ins06.count)
        for (row, expected) in zip(rows, fixture.expected.ins06) {
            #expect(row.storeId == expected.storeId)
            #expect(row.code == expected.code)
            #expect(row.first.priceMinor == expected.firstMinor)
            #expect(row.latest.priceMinor == expected.latestMinor)
            #expect(abs(row.percent - expected.percent) < 0.001)
        }
    }

    @Test func ins07CheapestStoreForRegulars() {
        let rows = calculator.cheapestStores()
        #expect(rows.map(\.code) == fixture.expected.ins07.map(\.code))
        #expect(rows.map(\.cheapest.storeId) == fixture.expected.ins07.map(\.cheapestStoreId))
        #expect(rows.map(\.cheapest.priceMinor) == fixture.expected.ins07.map(\.cheapestMinor))
        #expect(rows.map(\.saving.amountMinor) == fixture.expected.ins07.map(\.savingMinor))
    }

    @Test func ins08CategorySplit() {
        let rows = calculator.categorySplit(in: calculator.interval(.month))
        #expect(rows.map(\.category) == fixture.expected.ins08_month.map(\.category))
        #expect(rows.map(\.total.amountMinor) == fixture.expected.ins08_month.map(\.totalMinor))
    }

    @Test func currenciesNeverMix() {
        let usd = InsightsCalculator(trips: fixture.trips, prices: fixture.prices, currency: "usd", now: fixture.now)
        #expect(usd.averageTrip()?.amountMinor == 100)
        #expect(usd.averageTrip()?.currency == "USD")
        #expect(!usd.hasEnoughData)
        #expect(calculator.hasEnoughData)
    }

    @Test func emptyHistory() {
        let empty = InsightsCalculator(trips: [], prices: [], currency: "EUR", now: fixture.now)
        #expect(empty.averageTrip() == nil)
        #expect(empty.spend(.month).deltaPercent == nil)
        #expect(empty.limitAdherence().rate == 0)
        #expect(empty.priceChanges().isEmpty)
    }
}
