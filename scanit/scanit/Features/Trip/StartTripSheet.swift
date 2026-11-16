import Algorithms
import ScanItCore
import SwiftData
import SwiftUI

/// Start a trip (`DESIGN.md` §2): store chips with the last one preselected, an optional limit
/// with chips from the user's history, and the currency. BACKLOG IOS-003. A new store can take a
/// chain from the country's list (CMP-001): one tap names the store and tags its chain.
struct StartTripSheet: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var options: TripStartOptions?
    @State private var selectedStoreID: UUID?
    @State private var isAddingStore = false
    @State private var newStoreName = ""
    /// `Chain.id` for the new store. Follows the typed name until a chip is tapped.
    @State private var newStoreChain: String?
    @State private var chainChosenByHand = false
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
                    .onChange(of: newStoreName) { _, name in
                        guard !chainChosenByHand else { return }
                        newStoreChain = ChainCatalog.match(storeName: name, country: country)?.id
                    }
                if !chains.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(chains) { chain in
                                Chip(title: chain.name, isSelected: newStoreChain == chain.id) {
                                    pickChain(chain)
                                }
                                .accessibilityIdentifier("chain.\(chain.id)")
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
            }
        }
    }

    private var country: String { Locale.current.region?.identifier ?? "PT" }
    private var chains: [Chain] { ChainCatalog.chains(country: country) }

    /// One tap: tags the chain and, when the name is empty or still another chain's name, names
    /// the store after it. A second tap on the same chip clears the chain.
    private func pickChain(_ chain: Chain) {
        chainChosenByHand = true
        if newStoreChain == chain.id {
            newStoreChain = nil
            return
        }
        let current = trimmedNewStoreName
        if current.isEmpty || chains.contains(where: { $0.name == current }) {
            newStoreName = chain.name
        }
        newStoreChain = chain.id
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
        Array([currency, Locale.current.currency?.identifier ?? "EUR", "EUR", "USD", "GBP"].uniqued())
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
            let created = Store(name: trimmedNewStoreName, chain: newStoreChain, countryCode: country, currency: currency)
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
