import Foundation
import StoreKitTest
import Testing
@testable import scanit

struct PaywallPolicyTests {
    private let on = PaywallPolicy(isEnabled: true, freeTripsPerMonth: 4, visibleHistory: 10)

    @Test func fifthTripOfTheMonthNeedsTheUnlock() {
        #expect(on.canStartTrip(tripsThisMonth: 3, isUnlimited: false))
        #expect(!on.canStartTrip(tripsThisMonth: 4, isUnlimited: false))
        #expect(on.canStartTrip(tripsThisMonth: 40, isUnlimited: true))
    }

    @Test func offUntilLaunch() {
        #expect(!PaywallPolicy.launch.isEnabled, "testers in the strangers gate are never limited")
        #expect(PaywallPolicy.launch.canStartTrip(tripsThisMonth: 99, isUnlimited: false))
        #expect(PaywallPolicy.launch.visibleTrips(Array(1...30), isUnlimited: false).hiddenCount == 0)
    }

    @Test func olderTripsAreHiddenNotDeleted() {
        let trips = Array(1...13) // newest first
        let split = on.visibleTrips(trips, isUnlimited: false)
        #expect(split.visible == Array(1...10))
        #expect(split.hiddenCount == 3)
        #expect(on.visibleTrips(trips, isUnlimited: true).visible.count == 13)
        #expect(on.visibleTrips(Array(1...10), isUnlimited: false).hiddenCount == 0)
    }

    @Test func onlyThisCalendarMonthCounts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = try Date("2026-10-09T12:00:00Z", strategy: .iso8601)
        let dates = try ["2026-10-01T00:00:00Z", "2026-10-09T08:00:00Z", "2026-09-30T23:59:59Z", "2026-11-01T00:00:00Z"]
            .map { try Date($0, strategy: .iso8601) }
        #expect(PaywallPolicy.tripsCounted(startedAt: dates, now: now, calendar: calendar) == 2)
    }
}

/// The real StoreKit 2 flow against the local `ScanIt.storekit` configuration: no dialogs, no network.
@MainActor
@Suite(.serialized)
struct PurchaseStoreTests {
    private func session() throws -> SKTestSession {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "ScanIt.storekit")
        let session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test func buyingUnlocksAndARefundLocksAgain() async throws {
        let session = try session()
        // Even when an expectation throws: a purchase left on the simulator unlocks later runs.
        defer { session.clearTransactions() }
        let store = PurchaseStore()
        await store.loadProduct()
        #expect(store.product?.id == PurchaseStore.unlimitedProductID)
        await store.refreshEntitlement()
        #expect(!store.isUnlimited)

        #expect(await store.purchase() == .purchased)
        #expect(store.isUnlimited)

        // A fresh store (next launch, or offline) reads the entitlement from the device.
        let relaunched = PurchaseStore()
        await relaunched.refreshEntitlement()
        #expect(relaunched.isUnlimited)

        // Refunded → no longer unlocked.
        let transaction = try #require(session.allTransactions().first)
        try session.refundTransaction(identifier: UInt(transaction.identifier))
        // StoreKit applies the revocation asynchronously; give it up to 2 s.
        for _ in 0..<20 where relaunched.isUnlimited {
            try await Task.sleep(for: .milliseconds(100))
            await relaunched.refreshEntitlement()
        }
        #expect(!relaunched.isUnlimited)
    }
}
