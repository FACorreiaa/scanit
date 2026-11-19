import Foundation
import Testing
@testable import ScanItCore

/// `Fixtures/savings.json`: hand-computed expectations for INS-11…14, shared with Android.
private struct SavingsFixture: Decodable {
    struct StoreMissed: Decodable { let storeId: String; let missedMinor: Int }
    struct Line: Decodable {
        let code: String
        let referenceMinor: Int?
        let savingMinor, missedMinor: Int
        let cheaperStoreId: String?
    }
    struct Trip: Decodable {
        let id: String
        let savingMinor, missedMinor, unpricedLines: Int
        let lines: [Line]
        let missedByStore: [StoreMissed]
    }
    struct Month: Decodable {
        let offset, savingMinor, missedMinor, trips, comparedTrips: Int
        let missedByStore: [StoreMissed]
    }
    struct Currency: Decodable { let trips: [Trip]; let months: [Month] }

    let now: Date
    let trips: [TripSnapshot]
    let prices: [PriceSnapshot]
    let expected: [String: Currency]
}

@Suite("Savings (INS-11…14)")
struct SavingsTests {
    private let fixture: SavingsFixture

    init() throws {
        fixture = try WireCoding.decoder().decode(SavingsFixture.self, from: Fixtures.data("savings.json"))
    }

    private func calculator(_ currency: String) -> InsightsCalculator {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2 // Monday
        return InsightsCalculator(
            trips: fixture.trips, prices: fixture.prices, currency: currency, now: fixture.now, calendar: calendar
        )
    }

    private func trip(_ id: String) throws -> TripSnapshot {
        try #require(fixture.trips.first { $0.id == id })
    }

    @Test(arguments: ["EUR", "USD"])
    func ins11to13TripSaving(currency: String) throws {
        let calculator = calculator(currency)
        let expectedTrips = try #require(fixture.expected[currency]).trips
        for expected in expectedTrips {
            let result = try #require(calculator.tripSaving(try trip(expected.id)), "trip \(expected.id)")
            #expect(result.tripId == expected.id)
            #expect(result.saving == Money(amountMinor: expected.savingMinor, currency: currency), "trip \(expected.id)")
            #expect(result.missed == Money(amountMinor: expected.missedMinor, currency: currency), "trip \(expected.id)")
            #expect(result.unpricedLines == expected.unpricedLines, "trip \(expected.id)")
            #expect(result.lines.map(\.code) == expected.lines.map(\.code), "trip \(expected.id)")
            for (line, want) in zip(result.lines, expected.lines) {
                #expect(line.referenceMinor == want.referenceMinor, "\(expected.id) \(want.code)")
                #expect(line.saving.amountMinor == want.savingMinor, "\(expected.id) \(want.code)")
                #expect(line.missed.amountMinor == want.missedMinor, "\(expected.id) \(want.code)")
                #expect(line.cheaperElsewhere?.storeId == want.cheaperStoreId, "\(expected.id) \(want.code)")
            }
            #expect(result.missedByStore.map(\.storeId) == expected.missedByStore.map(\.storeId), "trip \(expected.id)")
            #expect(result.missedByStore.map(\.missed.amountMinor) == expected.missedByStore.map(\.missedMinor))
        }
    }

    @Test(arguments: ["EUR", "USD"])
    func ins14MonthSaving(currency: String) throws {
        let calculator = calculator(currency)
        for expected in try #require(fixture.expected[currency]).months {
            let result = calculator.savings(in: calculator.interval(.month, offset: expected.offset))
            #expect(result.saving == Money(amountMinor: expected.savingMinor, currency: currency), "offset \(expected.offset)")
            #expect(result.missed == Money(amountMinor: expected.missedMinor, currency: currency), "offset \(expected.offset)")
            #expect(result.trips == expected.trips, "offset \(expected.offset)")
            #expect(result.comparedTrips == expected.comparedTrips, "offset \(expected.offset)")
            #expect(result.missedByStore.map(\.storeId) == expected.missedByStore.map(\.storeId), "offset \(expected.offset)")
            #expect(result.missedByStore.map(\.missed.amountMinor) == expected.missedByStore.map(\.missedMinor))
        }
    }

    /// SAVE-003: six months oldest first, each equal to INS-14 for that month; months without a trip
    /// have nothing to compare rather than a saving of 0.
    @Test(arguments: ["EUR", "USD"])
    func ins14SixMonthTrend(currency: String) throws {
        let calculator = calculator(currency)
        let months = try #require(fixture.expected[currency]).months
        let trend = calculator.monthlySavings()
        #expect(trend.count == 6)
        #expect(trend.last?.month == calculator.interval(.month))
        #expect(zip(trend, trend.dropFirst()).allSatisfy { $0.month.end == $1.month.start }, "consecutive months")
        for (index, point) in trend.enumerated() {
            let offset = index - 5
            if let want = months.first(where: { $0.offset == offset }) {
                #expect(point.saving.saving.amountMinor == want.savingMinor, "offset \(offset)")
                #expect(point.saving.comparedTrips == want.comparedTrips, "offset \(offset)")
            } else {
                #expect(point.saving.trips == 0 && !point.saving.hasComparison, "offset \(offset)")
            }
        }
    }

    /// A trip whose products have no price at another store counts as a trip, not as a comparison.
    @Test func unpricedTripIsNotAComparison() throws {
        let unpriced = TripSnapshot(
            id: "T9", storeId: "L", storeName: "Lidl", currency: "EUR",
            startedAt: fixture.now.addingTimeInterval(-7200), endedAt: fixture.now.addingTimeInterval(-3600),
            limitMinor: nil, tillTotalMinor: nil,
            lines: [LineSnapshot(code: "04006381333931", codeKind: .gtin, name: nil, quantity: 1, unitPriceMinor: 129, category: nil)]
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let alone = InsightsCalculator(trips: [unpriced], prices: fixture.prices, currency: "EUR", now: fixture.now, calendar: calendar)
        let month = alone.savings(in: alone.interval(.month))
        #expect(month.trips == 1)
        #expect(month.comparedTrips == 0)
        #expect(!month.hasComparison)
        #expect(month.saving.amountMinor == 0)
    }

    @Test func currenciesNeverMix() throws {
        for trip in fixture.trips {
            let other = trip.currency == "EUR" ? "USD" : "EUR"
            #expect(calculator(other).tripSaving(trip) == nil, "trip \(trip.id) in \(other)")
        }
    }

    @Test func inStoreAndOpaqueCodesAreSkipped() throws {
        var trip = try trip("T1")
        trip.lines.append(LineSnapshot(code: "QR-PAYLOAD", codeKind: .opaque, name: nil, quantity: 1, unitPriceMinor: 500, category: nil))
        let result = try #require(calculator("EUR").tripSaving(trip))
        #expect(!result.lines.contains { $0.code == "02040123001506" || $0.code == "QR-PAYLOAD" })
        #expect(result.saving.amountMinor == 82)
    }
}
