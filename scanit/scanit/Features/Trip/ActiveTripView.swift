import ScanItCore
import SwiftUI

/// The trip in progress (`DESIGN.md` §3, BACKLOG IOS-004): hero total and limit bar, cart
/// newest first (swipe to delete, tap to edit), big Scan button bottom-centre, Finish beside it.
struct ActiveTripView: View {
    @Environment(SessionStore.self) private var sessions
    let session: ShoppingSession
    let onFinish: (ShoppingSession) -> Void

    @State private var isScanning = false
    @State private var editing: CartItemSelection?
    @State private var isConfirmingCancel = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text(itemCountText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TripTotalHeader(
                        total: session.total, limit: session.limit, status: session.limitStatus, announcesChanges: true
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            }

            Section {
                if session.liveItems.isEmpty {
                    ContentUnavailableView(
                        "Cart is empty",
                        systemImage: "barcode.viewfinder",
                        description: Text("Tap Scan and point at a barcode.")
                    )
                } else {
                    ForEach(session.liveItems.sorted { $0.scannedAt > $1.scannedAt }, id: \.id) { item in
                        Button {
                            editing = CartItemSelection(item: item)
                        } label: {
                            CartItemRow(item: item, currency: session.currency)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                sessions.remove(item)
                            }
                        }
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
        .safeAreaInset(edge: .bottom) { actions }
        .confirmationDialog("Cancel this trip?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
            Button("Cancel trip", role: .destructive) { sessions.cancelTrip() }
            Button("Keep shopping", role: .cancel) {}
        } message: {
            Text("It won't count in your history.")
        }
        .fullScreenCover(isPresented: $isScanning) {
            ScannerScreen(session: session)
        }
        .sheet(item: $editing) { selection in
            EditItemSheet(item: selection.item, currency: session.currency)
                .presentationDetents([.medium])
        }
        .sensoryFeedback(trigger: sessions.feedback) { _, event in
            switch event?.kind {
            case .warning: .warning
            case .error: .error
            case nil: nil
            }
        }
    }

    /// Scan and Finish side by side; stacked when large text would wrap "Scan".
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                scanButton
                finishButton
            }
            VStack(spacing: 8) {
                scanButton
                finishButton
            }
        }
        .controlSize(.large)
        // The bar must not swallow the cart at the largest sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var scanButton: some View {
        Button {
            isScanning = true
        } label: {
            Label("Scan", systemImage: "barcode.viewfinder")
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("scan")
    }

    private var finishButton: some View {
        Button {
            if let finished = sessions.finishTrip() { onFinish(finished) }
        } label: {
            Text("Finish")
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.bordered)
        .disabled(session.liveItems.isEmpty)
        .accessibilityIdentifier("finishTrip")
    }

    private var itemCountText: String {
        let count = session.itemCount
        return count == 1 ? "1 item" : "\(count) items"
    }
}

/// `sheet(item:)` payload. SwiftData models are not reliably `Identifiable` for SwiftUI across
/// Xcode versions (see ARCHITECTURE.md), so wrap them.
struct CartItemSelection: Identifiable {
    let item: CartItem
    var id: UUID { item.id }
}

struct CartItemRow: View {
    @Environment(\.modelContext) private var context
    let item: CartItem
    let currency: String

    var body: some View {
        // Side by side when it fits; at large text sizes the price drops under the name
        // instead of wrapping mid-number.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                details
                Spacer()
                price
            }
            VStack(alignment: .leading, spacing: 4) {
                details
                price
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        HStack(spacing: 12) {
            ProductThumbnail(url: item.imageURL)
            text
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.productName ?? "Product")
                .lineLimit(2)
            Text(item.scannedCode.displayValue)
                .font(.caption)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(.secondary)
            if let trend = PriceTrend.lookup(code: item.code, store: item.session?.store, context: context) {
                // Secondary ink, not red: red is reserved for the limit (DESIGN.md → Do not).
                Text("\(trend.roundedPercent > 0 ? "↑" : "↓") \(abs(trend.roundedPercent))% since \(trend.since, format: .dateTime.month(.wide))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Price \(trend.roundedPercent > 0 ? "up" : "down") \(abs(trend.roundedPercent)) percent here since \(trend.since.formatted(.dateTime.month(.wide)))")
            }
        }
    }

    private var price: some View {
        HStack(spacing: 4) {
            if item.priceSource == .remembered {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remembered price")
            }
            Text(priceText)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var priceText: String {
        let unit = Money(amountMinor: item.unitPriceMinor, currency: currency)
        return item.quantity > 1 ? "\(item.quantity) × \(unit.formatted())" : unit.formatted()
    }
}

/// Open Food Facts photo, or a quiet placeholder (no photo, or offline).
struct ProductThumbnail: View {
    let url: URL?
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 40

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Image(systemName: "shippingbox")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
