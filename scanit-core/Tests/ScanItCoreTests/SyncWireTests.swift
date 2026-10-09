import Foundation
import Testing
@testable import ScanItCore

@Suite("Sync wire contract")
struct SyncWireTests {
    @Test func decodesPushFixture() throws {
        let request = try WireCoding.decoder().decode(SyncPushRequest.self, from: Fixtures.data("sync-push.json"))
        #expect(request.changes.count == 4)

        guard case .store(let store) = request.changes[0].payload else {
            Issue.record("first change should be a store"); return
        }
        #expect(store.chain == "Pingo Doce")

        guard case .session(let session) = request.changes[1].payload else {
            Issue.record("second change should be a session"); return
        }
        #expect(session.limit == Money(amountMinor: 6000, currency: "EUR"))
        #expect(session.status == .finished)

        guard case .cartItem(let item) = request.changes[2].payload else {
            Issue.record("third change should be a cart item"); return
        }
        #expect(item.codeKind == .gtin)
        #expect(item.weightGrams == nil)
        #expect(item.priceSource == .ocr)

        #expect(request.changes[3].entity == .priceObservation)
        #expect(request.changes[3].deletedAt != nil)
    }

    @Test func fractionalSecondsAreAccepted() throws {
        let request = try WireCoding.decoder().decode(SyncPushRequest.self, from: Fixtures.data("sync-push.json"))
        let updatedAt = request.changes[1].updatedAt.timeIntervalSince1970
        #expect(abs(updatedAt.truncatingRemainder(dividingBy: 1) - 0.25) < 0.001)
    }

    @Test func roundTrips() throws {
        let original = try WireCoding.decoder().decode(SyncPushRequest.self, from: Fixtures.data("sync-push.json"))
        let encoded = try WireCoding.encoder().encode(original)
        let decoded = try WireCoding.decoder().decode(SyncPushRequest.self, from: encoded)
        #expect(decoded == original)
    }

    @Test func entityNamesMatchTheContract() throws {
        let encoded = try WireCoding.encoder().encode(
            try WireCoding.decoder().decode(SyncPushRequest.self, from: Fixtures.data("sync-push.json"))
        )
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let entities = (object?["changes"] as? [[String: Any]])?.compactMap { $0["entity"] as? String }
        #expect(entities == ["store", "session", "cart_item", "price_observation"])
    }

    @Test func unknownEntityFails() {
        let json = #"{"changes":[{"entity":"coupon","id":"5b1f2c4e-0d7a-4a43-9c1e-2f3b4a5c6d01","updatedAt":"2026-10-09T10:00:00Z","data":{}}]}"#
        #expect(throws: DecodingError.self) {
            try WireCoding.decoder().decode(SyncPushRequest.self, from: Data(json.utf8))
        }
    }
}
