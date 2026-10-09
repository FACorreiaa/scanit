import Foundation
import ScanItCore
import SwiftData
import Testing
@testable import scanit

/// Stand-in for Open Food Facts: answers from a table, or fails like a phone with no signal.
private final class StubLookup: ProductLookup, @unchecked Sendable {
    var answers: [String: ProductLookupResult] = [:]
    var isOffline = false
    private(set) var asked: [String] = []

    func lookup(code: String) async throws -> ProductLookupResult {
        asked.append(code)
        if isOffline { throw URLError(.notConnectedToInternet) }
        return answers[code] ?? .notFound
    }
}

private func fixture(_ name: String) throws -> Data {
    let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    return try Data(contentsOf: url)
}

private let milkCode = ScannedCode(kind: .gtin, value: "05601234567892")
private let nutellaCode = ScannedCode(kind: .gtin, value: "03017620422003")

struct OpenFoodFactsParsingTests {
    @Test func parsesAFoundProduct() throws {
        let result = try OpenFoodFactsClient.parse(fixture("off-found.json"))
        guard case .found(let info) = result else { Issue.record("expected found"); return }
        #expect(info.name == "Nutella")
        #expect(info.brand == "Nutella", "first brand only")
        #expect(info.imageURL?.host() == "images.openfoodfacts.org")
        #expect(info.categories.first == "en:breakfasts")
    }

    @Test func parsesNotFound() throws {
        #expect(try OpenFoodFactsClient.parse(fixture("off-missing.json")) == .notFound)
    }

    @Test func displayNameAvoidsRepeatingTheBrand() {
        let nutella = Product(gtin: "x")
        nutella.name = "Nutella"; nutella.brand = "Nutella"
        #expect(nutella.displayName == "Nutella")
        let milk = Product(gtin: "y")
        milk.name = "Leite meio gordo"; milk.brand = "Mimosa"
        #expect(milk.displayName == "Leite meio gordo · Mimosa")
    }
}

@MainActor
struct ProductEnricherTests {
    private func setup() throws -> (ModelContext, SessionStore, ProductEnricher, StubLookup) {
        let context = ModelContext(try ScanItSchema.container(inMemory: true))
        let lookup = StubLookup()
        let sessions = SessionStore(context: context)
        sessions.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        return (context, sessions, ProductEnricher(context: context, lookup: lookup), lookup)
    }

    @Test func fillsNameAndPhotoAfterAdd() async throws {
        let (_, sessions, enricher, lookup) = try setup()
        lookup.answers["3017620422003"] = .found(ProductInfo(
            name: "Nutella", brand: "Ferrero", imageURL: URL(string: "https://example.com/n.jpg"), categories: []
        ))
        let item = try #require(sessions.addItem(code: nutellaCode, unitPriceMinor: 399, priceSource: .manual))
        enricher.enqueue(item)
        #expect(item.productName == nil, "adding never waits for the network")

        await enricher.flush()
        #expect(lookup.asked == ["3017620422003"], "asks with the 13-digit code printed on the pack")
        #expect(item.productName == "Nutella · Ferrero")
        #expect(item.imageURL?.absoluteString == "https://example.com/n.jpg")
    }

    @Test func offlineItemsAreQueuedAndFilledWhenBackOnline() async throws {
        let (_, sessions, enricher, lookup) = try setup()
        lookup.isOffline = true
        lookup.answers["5601234567892"] = .found(ProductInfo(name: "Leite", brand: nil, imageURL: nil, categories: []))
        lookup.answers["3017620422003"] = .found(ProductInfo(name: "Nutella", brand: nil, imageURL: nil, categories: []))
        let milk = try #require(sessions.addItem(code: milkCode, unitPriceMinor: 99, priceSource: .manual))
        let nutella = try #require(sessions.addItem(code: nutellaCode, unitPriceMinor: 399, priceSource: .manual))
        enricher.enqueue(milk); enricher.enqueue(nutella)

        await enricher.flush()
        #expect(milk.productName == nil)
        #expect(lookup.asked.count == 1, "stops at the first network error instead of hammering")

        lookup.isOffline = false
        await enricher.flush()
        #expect(milk.productName == "Leite")
        #expect(nutella.productName == "Nutella")
    }

    @Test func knownProductIsNamedImmediatelyWithoutNetwork() async throws {
        let (_, sessions, enricher, lookup) = try setup()
        lookup.answers["5601234567892"] = .found(ProductInfo(name: "Leite", brand: nil, imageURL: nil, categories: []))
        enricher.enqueue(try #require(sessions.addItem(code: milkCode, unitPriceMinor: 99, priceSource: .manual)))
        await enricher.flush()

        lookup.isOffline = true
        let again = try #require(sessions.addItem(code: milkCode, unitPriceMinor: 99, priceSource: .manual))
        enricher.enqueue(again)
        #expect(again.productName == "Leite")
        #expect(enricher.cached(milkCode)?.displayName == "Leite")
        #expect(lookup.asked.count == 1)
    }

    @Test func missesAreCachedAndRetriedAfterAWeek() async throws {
        let context = ModelContext(try ScanItSchema.container(inMemory: true))
        let lookup = StubLookup()
        var clock = Date(timeIntervalSince1970: 1_790_000_000)
        let sessions = SessionStore(context: context)
        sessions.startTrip(store: nil, limitMinor: nil, currency: "EUR")
        let enricher = ProductEnricher(context: context, lookup: lookup, now: { clock })

        enricher.enqueue(try #require(sessions.addItem(code: milkCode, unitPriceMinor: 99, priceSource: .manual)))
        await enricher.flush()
        await enricher.flush()
        #expect(lookup.asked.count == 1, "a miss is not asked again straight away")

        clock += ProductEnricher.missRetryInterval + 1
        await enricher.flush()
        #expect(lookup.asked.count == 2)
    }

    @Test func inStoreAndOpaqueCodesAreNeverLookedUp() async throws {
        let (_, sessions, enricher, lookup) = try setup()
        let produce = ScannedCode(kind: .gtin, value: "02040123001506")
        let promo = ScannedCode(kind: .opaque, value: "https://example.com/promo")
        enricher.enqueue(try #require(sessions.addItem(code: produce, unitPriceMinor: 250, priceSource: .manual)))
        enricher.enqueue(try #require(sessions.addItem(code: promo, unitPriceMinor: 10, priceSource: .manual)))
        await enricher.flush()
        #expect(lookup.asked.isEmpty)
    }

    @Test func userEditedNameIsNeverOverwritten() async throws {
        let (_, sessions, enricher, lookup) = try setup()
        lookup.answers["5601234567892"] = .found(ProductInfo(name: "Leite", brand: nil, imageURL: nil, categories: []))
        let item = try #require(sessions.addItem(code: milkCode, productName: "Milk for Ana", unitPriceMinor: 99, priceSource: .manual))
        enricher.enqueue(item)
        await enricher.flush()
        #expect(item.productName == "Milk for Ana")
    }
}

/// Real Open Food Facts call. Opt-in only (`TEST_RUNNER_SCANIT_LIVE_OFF=1`), never in CI.
struct OpenFoodFactsLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCANIT_LIVE_OFF"] == "1"))
    func knownProductAnswersWithinTwoSeconds() async throws {
        let start = Date()
        let result = try await OpenFoodFactsClient().lookup(code: "3017620422003")
        let elapsed = Date().timeIntervalSince(start)
        guard case .found(let info) = result else { Issue.record("Nutella should be in OFF"); return }
        #expect(info.name == "Nutella")
        #expect(info.imageURL != nil)
        #expect(elapsed < 2, "took \(elapsed)s")
        print("OFF live lookup: \(String(format: "%.2f", elapsed))s")
    }
}
