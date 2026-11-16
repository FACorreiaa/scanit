import ScanItCore
import SwiftUI

/// Confirm a scanned product (`DESIGN.md` §4, BACKLOG IOS-007/008/009). A remembered price or one
/// read from the shelf label is prefilled, so a known product is two taps: scan, Add. Other prices
/// on the label are one-tap chips. Otherwise the price keypad opens.
struct ConfirmItemSheet: View {
    let detected: DetectedCode
    let currency: String
    let remembered: RememberedPrice?
    /// Open Food Facts details, when this product has been seen before.
    var product: Product? = nil
    /// What the shelf label offered, when the price step read one.
    var offer: LabelPriceOffer? = nil
    /// The cheapest other store for this product, shown when it beats the price being added.
    var elsewhere: PriceElsewhere? = nil
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
                } footer: {
                    // Attribution required by Open Food Facts' licences (ODbL data, CC BY-SA images).
                    if product?.displayName != nil || product?.imageURL != nil {
                        Text("Product data: Open Food Facts")
                    }
                }

                Section {
                    if let chips = offer?.chips, !chips.isEmpty {
                        labelChips(chips)
                    }
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
                    VStack(alignment: .leading, spacing: 4) {
                        if offer?.prefill != nil {
                            Label("Read from the shelf label. Check it matches.", systemImage: "text.viewfinder")
                        } else if offer != nil {
                            Text("Pick the price, or type it.")
                        } else if let remembered {
                            Label {
                                Text("Seen here \(remembered.observedAt, format: .relative(presentation: .named))")
                            } icon: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                        }
                        if let elsewhere, elsewhere.isCheaper(than: price) {
                            ElsewhereLabel(elsewhere: elsewhere)
                        }
                    }
                }
            }
            .contentMargins(.bottom, 12, for: .scrollContent)
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
            if let prefill = offer?.prefill {
                priceText = MoneyInput.editingText(prefill)
            } else if offer != nil {
                priceFocused = false
            } else if let remembered, remembered.price.currency == currency {
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

    private func labelChips(_ chips: [Money]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button(chip.formatted()) { priceText = MoneyInput.editingText(chip) }
                        .buttonStyle(.bordered)
                        .monospacedDigit()
                        .accessibilityIdentifier("labelChip")
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func add() {
        guard let price else { return }
        let source = PriceSourceResolver.resolve(
            price: price, prefill: offer?.prefill, labelCandidates: offer?.chips ?? [], remembered: remembered?.price
        )
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
