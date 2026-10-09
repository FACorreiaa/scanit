import ScanItCore
import SwiftData
import SwiftUI

/// Start a trip (`DESIGN.md` §2): store chips with the last one preselected, an optional limit
/// with chips from the user's history, and the currency. BACKLOG IOS-003.
struct StartTripSheet: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var options: TripStartOptions?
    @State private var selectedStoreID: UUID?
    @State private var isAddingStore = false
    @State private var newStoreName = ""
    @State private var limitText = ""
    @State private var currency = Locale.current.currency?.identifier ?? "EUR"
    @FocusState private var focusedField: Field?

    private enum Field { case storeName, limit }

    var body: some View {
        NavigationStack {
            Form {
                storeSection
                limitSection
                Section {
                    Picker("Currency", selection: $currency) {
                        ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            .navigationTitle("New trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: start) {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canStart)
                .padding(16)
                .accessibilityIdentifier("startTrip")
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Sections

    private var storeSection: some View {
        Section("Store") {
            if let stores = options?.recentStores, !stores.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stores, id: \.id) { store in
                            Chip(title: store.name, isSelected: !isAddingStore && selectedStoreID == store.id) {
                                isAddingStore = false
                                selectedStoreID = store.id
                                currency = store.currency
                            }
                        }
                        Chip(title: "New store", systemImage: "plus", isSelected: isAddingStore) {
                            isAddingStore = true
                            focusedField = .storeName
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
            if isAddingStore {
                TextField("Store name", text: $newStoreName)
                    .textInputAutocapitalization(.words)
                    .focused($focusedField, equals: .storeName)
                    .accessibilityIdentifier("storeName")
            }
        }
    }

    private var limitSection: some View {
        Section {
            HStack {
                Text(currencySymbol).foregroundStyle(.secondary)
                TextField("No limit", text: $limitText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .limit)
                    .accessibilityIdentifier("limit")
            }
            let suggestions = options?.limitSuggestions(currency: currency) ?? []
            if !suggestions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Chip(title: chipTitle(suggestion), isSelected: parsedLimit == suggestion.amount) {
                            limitText = MoneyInput.editingText(suggestion.amount)
                        }
                    }
                }
            }
        } header: {
            Text("Limit")
        } footer: {
            Text("Optional. You'll see how much is left as you scan.")
        }
    }

    // MARK: - Logic

    private var canStart: Bool {
        let hasStore = isAddingStore ? !trimmedNewStoreName.isEmpty : selectedStoreID != nil
        let limitIsValid = limitText.trimmingCharacters(in: .whitespaces).isEmpty || (parsedLimit?.amountMinor ?? 0) > 0
        return hasStore && limitIsValid
    }

    private var trimmedNewStoreName: String {
        newStoreName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedLimit: Money? {
        MoneyInput.parse(limitText, currency: currency)
    }

    private var currencySymbol: String {
        Money.symbol(for: currency)
    }

    private var currencyChoices: [String] {
        var choices = [currency, Locale.current.currency?.identifier ?? "EUR", "EUR", "USD", "GBP"]
        var seen = Set<String>()
        choices = choices.filter { seen.insert($0).inserted }
        return choices
    }

    private func chipTitle(_ suggestion: TripStartOptions.LimitSuggestion) -> String {
        switch suggestion.kind {
        case .lastLimit: "Last \(suggestion.amount.formatted())"
        case .averageTrip: "Usual \(suggestion.amount.formatted())"
        }
    }

    private func load() {
        let options = TripStartOptions(context: context)
        self.options = options
        if let last = options.lastUsedStore {
            selectedStoreID = last.id
            currency = last.currency
        } else {
            isAddingStore = true
            focusedField = .storeName
        }
    }

    private func start() {
        let store: Store?
        if isAddingStore {
            let created = Store(
                name: trimmedNewStoreName,
                countryCode: Locale.current.region?.identifier ?? "PT",
                currency: currency
            )
            context.insert(created)
            store = created
        } else {
            store = options?.recentStores.first { $0.id == selectedStoreID }
        }
        sessions.startTrip(store: store, limitMinor: parsedLimit?.amountMinor, currency: currency)
        dismiss()
    }
}

/// Capsule choice button. Selected uses the prominent style; one selected value per group.
private struct Chip: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        if isSelected {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
