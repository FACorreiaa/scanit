import ScanItCore
import SwiftUI

/// Fix quantity or price of a cart line, in the active trip or a past one (IOS-004, IOS-011).
struct EditItemSheet: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(\.dismiss) private var dismiss

    let item: CartItem
    let currency: String

    @State private var priceText = ""
    @State private var quantity = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                        TextField("0,00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .accessibilityIdentifier("editPrice")
                    }
                    Stepper(value: $quantity, in: 1...99) {
                        Text("Quantity \(quantity)")
                    }
                } header: {
                    Text(item.productName ?? item.scannedCode.displayValue)
                }

                Section {
                    Button("Remove from cart", role: .destructive) {
                        sessions.remove(item)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(price == nil)
                        .accessibilityIdentifier("saveItem")
                }
            }
        }
        .onAppear {
            priceText = MoneyInput.editingText(Money(amountMinor: item.unitPriceMinor, currency: currency))
            quantity = item.quantity
        }
    }

    private var price: Money? {
        MoneyInput.parse(priceText, currency: currency).flatMap { $0.amountMinor > 0 ? $0 : nil }
    }

    private func save() {
        guard let price else { return }
        sessions.update(
            item,
            quantity: quantity == item.quantity ? nil : quantity,
            unitPriceMinor: price.amountMinor == item.unitPriceMinor ? nil : price.amountMinor
        )
        dismiss()
    }
}
