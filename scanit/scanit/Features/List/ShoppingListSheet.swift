import SwiftData
import SwiftUI

/// The shopping list (BACKLOG ADD-005): written before the trip, ticked by scanning or by hand.
struct ShoppingListSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<ListItem> { $0.deletedAt == nil }, sort: \ListItem.createdAt)
    private var lines: [ListItem]

    @State private var text = ""
    @FocusState private var isAdding: Bool

    var body: some View {
        let suggestions = ShoppingList.suggestions(for: text, context: context)
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
                Text(line.text)
                    .strikethrough(line.isDone)
                    .foregroundStyle(line.isDone ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityLabel(line.text)
        .accessibilityValue(line.isDone ? "Ticked" : "To get")
        .accessibilityIdentifier("listLine")
    }
}

/// "Shopping list · 3 to get": opens the list from the Trip tab, with or without a trip.
struct ShoppingListButton: View {
    @Query(filter: #Predicate<ListItem> { $0.deletedAt == nil && $0.doneAt == nil })
    private var waiting: [ListItem]
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Label(title, systemImage: "checklist")
        }
        .accessibilityIdentifier("shoppingList")
        .sheet(isPresented: $isShowing) {
            ShoppingListSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private var title: String {
        waiting.isEmpty ? "Shopping list" : "Shopping list · \(waiting.count) to get"
    }
}
