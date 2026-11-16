import ScanItCore
import SwiftUI

/// An item the scanner added without a confirm step, kept while its banner is on screen.
struct AddedItem: Identifiable {
    let id = UUID()
    let item: CartItem
    let price: Money
    let source: PriceSource
    /// When the remembered price was last seen here.
    let seenAt: Date?
    /// Set when another store is known to sell it for less.
    let elsewhere: PriceElsewhere?
}

/// Says what was just added and where the price came from, with the way back: Undo, or Edit for
/// a wrong price or more than one. The scanner keeps running underneath.
struct AddedItemBanner: View {
    let added: AddedItem
    let name: String
    let onUndo: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Added · \(added.price.formatted())")
                    .font(.headline)
                    .monospacedDigit()
                    .accessibilityIdentifier("addedTitle")
                Text(name)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                origin
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let elsewhere = added.elsewhere {
                    ElsewhereLabel(elsewhere: elsewhere)
                        .font(.footnote.weight(.medium))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button(action: onUndo) {
                    Text("Undo").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("undoAdd")

                Button(action: onEdit) {
                    Text("Edit").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("editAdded")
            }
            .controlSize(.large)
            .tint(.white)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var origin: some View {
        if let seenAt = added.seenAt {
            Text("Seen here \(seenAt, format: .relative(presentation: .named))")
        } else if added.source == .ocr {
            Text("Read from the shelf label")
        }
    }
}

/// "€1,79 at Aldi · 12 Oct": the same product, cheaper in another store.
struct ElsewhereLabel: View {
    let elsewhere: PriceElsewhere

    var body: some View {
        Label {
            Text("\(elsewhere.price.formatted()) at \(elsewhere.storeName) · \(elsewhere.observedAt, format: .dateTime.day().month(.abbreviated))")
                .monospacedDigit()
        } icon: {
            Image(systemName: "arrow.down.circle")
        }
        .accessibilityIdentifier("cheaperElsewhere")
    }
}
