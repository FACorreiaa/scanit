import Foundation
import ScanItCore
import SwiftData
import Testing
@testable import scanit

private func eur(_ minor: Int) -> Money { Money(amountMinor: minor, currency: "EUR") }
private let milk = ScannedCode(kind: .gtin, value: "05601234567892")

// MARK: - IOS-007 price source

struct PriceSourceResolverTests {
    @Test func prefilledLabelPriceAddedUnchangedIsOCR() {
        let source = PriceSourceResolver.resolve(price: eur(249), prefill: eur(249), labelCandidates: [eur(249)], remembered: eur(229))
        #expect(source == .ocr)
        #expect(PriceSourceResolver.outcome(source: source, prefill: eur(249), labelCandidates: [eur(249)]) == .accepted)
    }

    @Test func changingThePrefillIsAnEdit() {
        let typed = PriceSourceResolver.resolve(price: eur(239), prefill: eur(249), labelCandidates: [eur(249)], remembered: nil)
        #expect(typed == .ocrEdited)
        let tookRemembered = PriceSourceResolver.resolve(price: eur(229), prefill: eur(249), labelCandidates: [eur(249)], remembered: eur(229))
        #expect(tookRemembered == .ocrEdited, "the label prefill was overridden")
        #expect(PriceSourceResolver.outcome(source: typed, prefill: eur(249), labelCandidates: [eur(249)]) == .edited)
    }

    @Test func pickingALabelChipWithoutPrefillIsAnEdit() {
        let source = PriceSourceResolver.resolve(price: eur(199), prefill: nil, labelCandidates: [eur(249), eur(199)], remembered: nil)
        #expect(source == .ocrEdited)
    }

    @Test func noLabelReadKeepsTodaysRules() {
        #expect(PriceSourceResolver.resolve(price: eur(229), prefill: nil, labelCandidates: [], remembered: eur(229)) == .remembered)
        let typed = PriceSourceResolver.resolve(price: eur(100), prefill: nil, labelCandidates: [], remembered: eur(229))
        #expect(typed == .manual)
        #expect(PriceSourceResolver.outcome(source: typed, prefill: nil, labelCandidates: []) == .none)
    }
}

// MARK: - IOS-007 field metrics

@MainActor
struct OCRStatsTests {
    @Test func countsSourcesAndSkipsDeletedItems() throws {
        let items = [
            CartItem(code: milk, unitPriceMinor: 99, priceSource: .ocr),
            CartItem(code: milk, unitPriceMinor: 99, priceSource: .ocr),
            CartItem(code: milk, unitPriceMinor: 99, priceSource: .ocrEdited),
            CartItem(code: milk, unitPriceMinor: 99, priceSource: .ocrCorrected),
            CartItem(code: milk, unitPriceMinor: 99, priceSource: .manual),
        ]
        let deleted = CartItem(code: milk, unitPriceMinor: 99, priceSource: .ocr)
        deleted.softDelete()

        let stats = OCRStats(items: items + [deleted])
        #expect(stats.scanned == 5)
        #expect(stats.accepted == 2)
        #expect(stats.edited == 1)
        #expect(stats.corrected == 1)
        #expect(stats.acceptedShare == 0.4)
        #expect(stats.correctedShare == 0.25)
        #expect(OCRStats(items: []).acceptedShare == nil)
    }

    @Test func correctingALabelPriceInHistoryIsCountedAndTracked() throws {
        final class Recording: AnalyticsClient, @unchecked Sendable {
            var events: [AnalyticsEvent] = []
            func track(_ event: AnalyticsEvent) { events.append(event) }
        }
        let analytics = Recording()
        let store = SessionStore(context: ModelContext(try ScanItSchema.container(inMemory: true)), analytics: analytics)
        store.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        let fromLabel = try #require(store.addItem(code: milk, unitPriceMinor: 249, priceSource: .ocr))
        let typed = try #require(store.addItem(code: milk, unitPriceMinor: 199, priceSource: .manual))

        store.update(fromLabel, unitPriceMinor: 229)
        store.update(typed, unitPriceMinor: 189)

        #expect(fromLabel.priceSource == .ocrCorrected)
        #expect(typed.priceSource == .manual)
        #expect(analytics.events.filter { $0 == .priceOCRCorrected }.count == 1)
    }

    @Test func ocrEventsCarryNoAmounts() {
        let event = AnalyticsEvent.priceOCRResult(outcome: .accepted, ms: 1840)
        #expect(event.name == "price_ocr_result")
        #expect(event.properties == ["outcome": "accepted", "ms": "1840"])
        #expect(AnalyticsEvent.priceOCRCorrected.properties.isEmpty)
    }
}
