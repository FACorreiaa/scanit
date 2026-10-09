import ScanItCore
import SwiftUI

/// The trip in progress. Interim version: total, limit and cart rows. Swipe-to-delete, edit,
/// Scan and Finish arrive with BACKLOG IOS-004, IOS-005 and IOS-010.
struct ActiveTripView: View {
    @Environment(SessionStore.self) private var sessions
    let session: ShoppingSession

    @State private var isConfirmingCancel = false

    var body: some View {
        List {
            Section {
                TripTotalHeader(total: session.total, limit: session.limit, status: session.limitStatus)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
            }

            Section {
                if session.liveItems.isEmpty {
                    ContentUnavailableView(
                        "Cart is empty",
                        systemImage: "barcode.viewfinder",
                        description: Text("Products you scan appear here.")
                    )
                } else {
                    ForEach(session.liveItems.sorted { $0.scannedAt > $1.scannedAt }) { item in
                        CartItemRow(item: item, currency: session.currency)
                    }
                }
            }
        }
        .navigationTitle(session.store?.name ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Cancel trip", systemImage: "xmark", role: .destructive) {
                        isConfirmingCancel = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .confirmationDialog("Cancel this trip?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Cancel trip", role: .destructive) { sessions.cancelTrip() }
            Button("Keep shopping", role: .cancel) {}
        } message: {
            Text("It won't count in your history.")
        }
        .sensoryFeedback(trigger: sessions.feedback) { _, event in
            switch event?.kind {
            case .warning: .warning
            case .error: .error
            case nil: nil
            }
        }
    }
}

private struct CartItemRow: View {
    let item: CartItem
    let currency: String

    var body: some View {
        HStack {
            Text(item.productName ?? item.code)
                .lineLimit(1)
            Spacer()
            Group {
                if item.quantity > 1 {
                    Text("\(item.quantity) × \(Money(amountMinor: item.unitPriceMinor, currency: currency).formatted())")
                } else {
                    Text(Money(amountMinor: item.unitPriceMinor, currency: currency).formatted())
                }
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}
