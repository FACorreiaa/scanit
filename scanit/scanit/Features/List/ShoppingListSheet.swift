import ScanItCore
import SwiftData
import SwiftUI

/// The shopping list (BACKLOG ADD-005): written before the trip, ticked by scanning or by hand.
/// Under the lines, what they cost at each store you know (MEAL-004).
struct ShoppingListSheet: View {
    /// Starts a trip at the cheapest store. `nil` during a trip, which hides the button.
    var onStart: ((TripPrefill) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ListItem> { $0.deletedAt == nil }, sort: \ListItem.createdAt)
    private var lines: [ListItem]

    @State private var text = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        let suggestions = ShoppingList.suggestions(for: text, context: context)
        // Recomputed whenever the lines change (the query drives the redraw).
        let estimate = ListEstimate.estimate(context: context)
        NavigationStack {
            List {
                Section {
                    TextField("Add an item", text: $text)
                        .focused($isAdding)
                        .submitLabel(.done)
                        .onSubmit { add(text, code: nil) }
                        .accessibilityIdentifier("listNewItem")
                    ForEach(suggestions) { suggestion in
                        Button {
                            add(suggestion.name, code: suggestion.code)
                        } label: {
                            Label(suggestion.name, systemImage: "clock.arrow.circlepath")
                        }
                        .foregroundStyle(.primary)
                    }
                } footer: {
                    Text("Something you bought before is ticked when you scan it. Anything else is ticked when the product's name matches, or by tapping it.")
                }

                if !lines.isEmpty {
                    Section {
                        ForEach(lines, id: \.id) { line in
                            ListLineRow(line: line)
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        ShoppingList.remove(line, context: context)
                                    }
                                }
                        }
                    }
                }

                if !estimate.stores.isEmpty {
                    ListCostSection(estimate: estimate, lines: lines, onStart: onStart)
                }
            }
            .navigationTitle("Shopping list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if lines.contains(where: \.isDone) {
                        Button("Clear ticked") { ShoppingList.clearDone(context: context) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("listDone")
                }
            }
        }
        .onAppear { isAdding = lines.isEmpty }
    }

    private func add(_ value: String, code: String?) {
        ShoppingList.add(value, code: code, context: context)
        text = ""
        isAdding = true
    }
}

/// One line: a tick box and the words. Colour is not the only signal, so a ticked line is also
/// struck through and says so to VoiceOver.
struct ListLineRow: View {
    @Environment(\.modelContext) private var context
    let line: ListItem

    var body: some View {
        Button {
            ShoppingList.toggle(line, context: context)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: line.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(line.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .font(.title3)
                Text(label)
                    .strikethrough(line.isDone)
                    .foregroundStyle(line.isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(line.isDone ? "Ticked" : "To get")
        .accessibilityIdentifier("listLine")
    }
}

extension ListLineRow {
    /// "2 × Pão de forma" when the list asks for more than one pack.
    var label: String { line.quantity > 1 ? "\(line.quantity) × \(line.text)" : line.text }
}

/// "Shopping list · 3 to get": opens the list from the Trip tab, with or without a trip.
struct ShoppingListButton: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(\.startTripFromList) private var startTripFromList
    @Query(filter: #Predicate<ListItem> { $0.deletedAt == nil && $0.doneAt == nil })
    private var waiting: [ListItem]
    @State private var isShowing = false
    /// The start sheet opens only after the list has fully closed.
    @State private var pendingStart: TripPrefill?

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Label(title, systemImage: "checklist")
        }
        .accessibilityIdentifier("shoppingList")
        .sheet(isPresented: $isShowing, onDismiss: {
            if let pendingStart {
                self.pendingStart = nil
                startTripFromList(pendingStart)
            }
        }) {
            ShoppingListSheet(onStart: sessions.active == nil ? { prefill in
                pendingStart = prefill
                isShowing = false
            } : nil)
                // The Trip tab's empty state centres its text, and a sheet inherits that.
                .multilineTextAlignment(.leading)
                .presentationDetents([.medium, .large])
        }
    }

    private var title: String {
        waiting.isEmpty ? "Shopping list" : "Shopping list · \(waiting.count) to get"
    }
}

/// "Lidl · €11,26", one row per store, best first, then **Start trip at Lidl**. A store missing some
/// prices says how many, and is never the one offered for being cheaper (`ListCost`).
private struct ListCostSection: View {
    let estimate: ListCostEstimate
    let lines: [ListItem]
    let onStart: ((TripPrefill) -> Void)?

    var body: some View {
        Section {
            ForEach(estimate.stores.prefix(3), id: \.storeId) { store in
                LabeledContent {
                    Text(store.total.formatted()).monospacedDigit()
                } label: {
                    Text(store.storeName ?? "A store")
                    if store.missingLines > 0 {
                        Text(store.missingLines == 1 ? "1 item not priced here" : "\(store.missingLines) items not priced here")
                    }
                }
                .accessibilityIdentifier("listCost.\(store.storeName ?? store.storeId)")
            }
            if let onStart, let cheapest = estimate.cheapest, let prefill = TripPrefill(estimate, lines: lines) {
                Button("Start trip at \(cheapest.storeName ?? "this store")", systemImage: "cart") {
                    onStart(prefill)
                }
                .accessibilityIdentifier("listStartTrip")
            }
        } header: {
            Text("Cost by store")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let base = "From the prices you've seen in the last 90 days."
        switch estimate.unpricedLines {
        case 0: return base
        case 1: return "1 item has no price yet. " + base
        default: return "\(estimate.unpricedLines) items have no price yet. " + base
        }
    }
}
