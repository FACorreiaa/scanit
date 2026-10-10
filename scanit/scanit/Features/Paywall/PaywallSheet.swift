import StoreKit
import SwiftUI

/// The unlock sheet (`DESIGN.md` §9). Shown only at Start trip after the free trips are used, or
/// from the locked row in History. Never during a trip, never on launch. Dismissable at no cost.
struct PaywallSheet: View {
    enum Reason: Equatable {
        case tripQuota(used: Int)
        case hiddenHistory(count: Int)
    }

    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    let reason: Reason
    var onUnlocked: () -> Void = {}

    @State private var message: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline)
                            .font(.title2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("ScanItNow Unlimited gives you unlimited trips and your full history.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    MascotView(height: 96)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Unlimited trips every month", systemImage: "cart")
                    Label("Every past trip in History", systemImage: "clock.arrow.circlepath")
                    Label("Pay once. No subscription.", systemImage: "checkmark.seal")
                }

                Spacer(minLength: 0)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await unlock() }
                    } label: {
                        Text(unlockTitle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(purchases.isWorking)
                    .accessibilityIdentifier("unlock")

                    HStack {
                        Button("Not now") { dismiss() }
                            .accessibilityIdentifier("notNow")
                        Spacer()
                        Button("Restore purchases") {
                            Task {
                                await purchases.restore()
                                if purchases.isUnlimited { finish() } else { message = "No earlier purchase found for this Apple account." }
                            }
                        }
                        .disabled(purchases.isWorking)
                    }
                    .font(.subheadline)
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .task { if purchases.product == nil { await purchases.loadProduct() } }
    }

    private var headline: String {
        switch reason {
        case .tripQuota(let used):
            used == 1 ? "You've done your free trip this month" : "You've done \(used) trips this month"
        case .hiddenHistory(let count):
            count == 1 ? "1 older trip is locked" : "\(count) older trips are locked"
        }
    }

    private var unlockTitle: String {
        guard let price = purchases.product?.displayPrice else { return "Unlock" }
        return "Unlock for \(price)"
    }

    private func unlock() async {
        message = nil
        switch await purchases.purchase() {
        case .purchased: finish()
        case .cancelled: break
        case .pending: message = "Waiting for approval. ScanItNow unlocks as soon as it's approved."
        case .failed: message = "The purchase didn't go through. Nothing was charged. Try again in a moment."
        }
    }

    private func finish() {
        dismiss()
        onUnlocked()
    }
}

extension EnvironmentValues {
    @Entry var paywallPolicy: PaywallPolicy = .launch
}
