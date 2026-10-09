import Foundation
import Observation
import OSLog
import StoreKit

/// "ScanIt Unlimited", a one-time non-consumable (`ARCHITECTURE.md` → Purchases, BACKLOG REL-003).
///
/// StoreKit 2 keeps verified entitlements on the device, so `isUnlimited` is right offline. No
/// receipt server in v1.
@Observable
final class PurchaseStore {
    static let unlimitedProductID = "com.fernandocorreia.scanit.unlimited"

    enum PurchaseOutcome: Equatable {
        case purchased, cancelled, pending, failed
    }

    private(set) var isUnlimited = false
    private(set) var product: StoreKit.Product?
    private(set) var isWorking = false

    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.fernandocorreia.scanit", category: "purchases")

    /// Starts listening for transactions made elsewhere (other device, Ask to Buy, refunds) and
    /// loads the current entitlement. Call once at launch.
    func start() async {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        await refreshEntitlement()
        await loadProduct()
    }

    func loadProduct() async {
        do {
            product = try await StoreKit.Product.products(for: [Self.unlimitedProductID]).first
        } catch {
            logger.info("product load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func purchase() async -> PurchaseOutcome {
        if product == nil { await loadProduct() }
        guard let product else { return .failed }
        isWorking = true
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
                return isUnlimited ? .purchased : .failed
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed
            }
        } catch {
            logger.error("purchase failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// "Restore purchases": asks the App Store to resync, then re-reads the entitlement.
    func restore() async {
        isWorking = true
        defer { isWorking = false }
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.unlimitedProductID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        isUnlimited = unlocked
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            logger.error("unverified transaction ignored")
            return
        }
        await transaction.finish()
        await refreshEntitlement()
    }
}
