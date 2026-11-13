import UIKit
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

@MainActor
struct LabelPriceOfferTests {
    private func offer(_ lines: [(String, Double)]) -> LabelPriceOffer {
        LabelPriceOffer(PriceParser(currency: "EUR").parse(lines.map { RecognizedText(text: $0.0, height: $0.1) }))
    }

    @Test func aClearLabelPrefillsWithoutChips() {
        let offer = offer([("1,99 €", 0.2), ("9,95 €/kg", 0.03)])
        #expect(offer.prefill == Money(amountMinor: 199, currency: "EUR"))
        #expect(offer.chips.isEmpty)
    }

    @Test func perKiloAndMultiBuyPricesAreNeverOffered() {
        let offer = offer([("9,95 €/kg", 0.2), ("2 x 0,99", 0.2)])
        #expect(offer.isEmpty)
    }

    @Test func twoSimilarPricesAreChipsAndNothingIsGuessed() {
        let offer = offer([("1,99 €", 0.2), ("2,49 €", 0.2)])
        #expect(offer.prefill == nil)
        #expect(offer.chips.count == 2)
    }

    @Test func aLabelWithNoPriceIsEmpty() {
        #expect(offer([("Leite meio gordo", 0.1)]).isEmpty)
    }

    /// Camera photos arrive rotated and Vision ignores the flag, so an unrotated still reads nothing.
    /// Pixels only: Vision's text recogniser cannot run on the simulator (`tools/label-bench` covers it).
    @Test func aRotatedPhotoIsRedrawnTheRightWayUp() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Left half red, right half blue; `.right` displays it turned clockwise, red on top.
        let pixels = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 150, height: 100))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 150, y: 0, width: 150, height: 100))
        }
        let photo = UIImage(cgImage: try #require(pixels.cgImage), scale: 1, orientation: .right)

        let upright = try #require(ShelfPriceReader.upright(photo))

        #expect(upright.width == 100)
        #expect(upright.height == 300)
        let context = try #require(CGContext(
            data: nil, width: 100, height: 300, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(upright, in: CGRect(x: 0, y: 0, width: 100, height: 300))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        #expect(bytes[400 * 10 + 200] > 200, "top row is red")
        #expect(bytes[400 * 290 + 200] < 50, "bottom row is not red")
    }

    @Test func aHugePhotoIsScaledDownForVision() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 4800, height: 1200), format: format).image { _ in }
        let upright = try #require(ShelfPriceReader.upright(photo))
        #expect(upright.width == 2400)
        #expect(upright.height == 600)
    }
}
