import ScanItCore
import SwiftData
import SwiftUI

/// Every store the user has added, with its chain (BACKLOG CMP-001). Stores made before chains
/// existed get one here; a store whose name looks like a chain offers it as a one-tap suggestion.
/// Lives under About until Settings exists (`DESIGN.md` §8).
struct StoresView: View {
    @Query(filter: #Predicate<Store> { $0.deletedAt == nil }, sort: \Store.name)
    private var stores: [Store]

    var body: some View {
        List {
            Section {
                ForEach(stores, id: \.id) { store in
                    StoreChainRow(store: store)
                }
            } footer: {
                Text("A chain lets ScanItNow compare prices between shops of the same chain.")
            }
        }
        .navigationTitle("Stores")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if stores.isEmpty {
                ContentUnavailableView("No stores yet", systemImage: "storefront",
                                       description: Text("Stores appear here after your first trip."))
            }
        }
    }
}

private struct StoreChainRow: View {
    @Bindable var store: Store

    private var chains: [Chain] { ChainCatalog.chains(country: store.countryCode) }
    private var suggestion: Chain? {
        store.chain == nil ? ChainCatalog.match(storeName: store.name, country: store.countryCode) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chains.isEmpty {
                LabeledContent(store.name, value: "No chains for \(store.countryCode)")
            } else {
                Picker(store.name, selection: chainBinding) {
                    Text("None").tag(String?.none)
                    ForEach(chains) { chain in
                        Text(chain.name).tag(Optional(chain.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("storeChain.\(store.name)")
            }
            if let suggestion {
                Button("Set to \(suggestion.name)") { setChain(suggestion.id) }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("suggestChain.\(store.name)")
            }
        }
    }

    private var chainBinding: Binding<String?> {
        // A closure, not `set: setChain`: passing the method itself crashes Swift 6.2.3's IRGen
        // (reabstraction thunk under NonisolatedNonsendingByDefault).
        Binding(get: { store.chain }, set: { setChain($0) })
    }

    private func setChain(_ id: String?) {
        guard store.chain != id else { return }
        store.chain = id
        store.touch()
    }
}

