import ScanItCore
import SwiftData
import SwiftUI

/// "Add to list" (BACKLOG MEAL-003): the week's ingredients merged into lines, in whole packs.
/// Untick what is already at home; that is remembered for next week.
struct PlanListSheet: View {
    let lines: [PlanListLine]
    let onAdd: (_ atHome: Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var atHome: Set<String>

    init(lines: [PlanListLine], onAdd: @escaping (_ atHome: Set<String>) -> Void) {
        self.lines = lines
        self.onAdd = onAdd
        _atHome = State(initialValue: Set(lines.filter(\.inPantry).map(\.key)))
    }

    var body: some View {
        let toGet = lines.count - atHome.count

        NavigationStack {
            List {
                Section {
                    ForEach(lines) { line in
                        PlanListRow(line: line, isAtHome: atHome.contains(line.key)) {
                            if atHome.contains(line.key) { atHome.remove(line.key) } else { atHome.insert(line.key) }
                        }
                    }
                } footer: {
                    Text("Untick what you already have at home. ScanItNow remembers it for next week.")
                }
            }
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionBar(
                    title: toGet == 1 ? "Add 1 item" : "Add \(toGet) items", identifier: "planListAdd"
                ) {
                    onAdd(atHome)
                    dismiss()
                }
                .disabled(toGet == 0)
            }
        }
    }
}

/// A tick box, "2 × Pão de forma", and the meals that need it.
private struct PlanListRow: View {
    let line: PlanListLine
    let isAtHome: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isAtHome ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(isAtHome ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.packs > 1 ? "\(line.packs) × \(line.text)" : line.text)
                        .foregroundStyle(isAtHome ? Color(.secondaryLabel) : Color(.label))
                    Text(isAtHome ? "At home" : line.meals.formatted(.list(type: .and)))
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Words in the label colour: a button would tint them, and only the tick box is the control.
        .foregroundStyle(Color(.label))
        .accessibilityElement(children: .combine)
        .accessibilityValue(isAtHome ? "At home" : "To get")
        .accessibilityIdentifier("planListLine")
    }
}
