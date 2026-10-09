import ScanItCore
import SwiftUI

/// Confirm a scanned product (`DESIGN.md` §4, BACKLOG IOS-008/IOS-009). A remembered price is
/// prefilled, so a known product is two taps: scan, Add. Otherwise the price keypad opens.
/// Shelf-price reading (IOS-007) will prefill the field from the camera too.
struct ConfirmItemSheet: View {
    let detected: DetectedCode
    let currency: String
    let remembered: RememberedPrice?
    /// Open Food Facts details, when this product has been seen before.
    var product: Product? = nil
    let onAdd: (_ quantity: Int, _ price: Money, _ source: PriceSource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var quantity = 1
    @FocusState private var priceFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        ProductThumbnail(url: product?.imageURL)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product?.displayName ?? (detected.code.kind == .gtin ? "Product" : "Item"))
                                .font(.headline)
                            Text(detected.code.displayValue)
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    HStack {
                        Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                        TextField("0,00", text: $priceText)
                            .keyboardType(.decimalPad)
                            .focused($priceFocused)
                            .font(.title3)
                            .monospacedDigit()
                            .accessibilityIdentifier("price")
                    }
                    Stepper(value: $quantity, in: 1...99) {
                        Text("Quantity \(quantity)")
                    }
                    .accessibilityIdentifier("quantity")
                } header: {
                    Text("Price")
                } footer: {
                    if let remembered {
                        Label {
                            Text("Seen here \(remembered.observedAt, format: .relative(presentation: .named))")
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                    }
                }
            }
            .navigationTitle("Add to cart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: add) {
                    Text(addTitle)
                        .frame(maxWidth: .infinity)
                        .monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(price == nil)
                .padding(16)
                .accessibilityIdentifier("addItem")
            }
        }
        .onAppear {
            if let remembered, remembered.price.currency == currency {
                priceText = MoneyInput.editingText(remembered.price)
            } else {
                priceFocused = true
            }
        }
    }

    private var price: Money? {
        MoneyInput.parse(priceText, currency: currency).flatMap { $0.amountMinor > 0 ? $0 : nil }
    }

    private var addTitle: String {
        guard let price else { return "Add" }
        return "Add · \(price.multiplied(by: quantity).formatted())"
    }

    private func add() {
        guard let price else { return }
        let source: PriceSource = price == remembered?.price ? .remembered : .manual
        onAdd(quantity, price, source)
        dismiss()
    }
}

extension Money {
    /// "€", "$", "£"… for a currency code, for field prefixes.
    static func symbol(for currency: String, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.currencySymbol
    }
}
