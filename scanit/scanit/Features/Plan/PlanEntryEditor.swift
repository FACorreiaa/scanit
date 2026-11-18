import ScanItCore
import SwiftData
import SwiftUI

/// One planned meal: how many it is for, what that costs, and a way to change or drop it.
struct PlanEntryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: PlanEntry
    let prices: [PriceSnapshot]
    let currency: String

    @State private var isPicking = false

    var body: some View {
        let request = SlotRequest(day: entry.day, slot: entry.slot)

        Form {
            if let meal = entry.meal {
                let planned = MealPlan.planned(entry, estimate: MealBook.estimate(meal, prices: prices, currency: currency))
                Section {
                    Text(meal.name)
                        .font(.title3)
                    Stepper(value: servingsBinding, in: MealBook.servingsRange) {
                        Text("For \(entry.servings)")
                    }
                    .accessibilityIdentifier("planServings")
                }

                Section {
                    LabeledContent("Cost", value: costText(planned))
                        .monospacedDigit()
                        .accessibilityIdentifier("planEntryCost")
                } footer: {
                    Text(footer(meal: meal, planned: planned))
                }

                Section {
                    NavigationLink("Edit meal") {
                        MealEditor(meal: meal, prices: prices, currency: currency)
                    }
                    Button("Change meal") { isPicking = true }
                        .accessibilityIdentifier("planChangeMeal")
                }

                Section {
                    Button("Remove from plan", role: .destructive) {
                        MealPlan.remove(entry, context: context)
                        dismiss()
                    }
                    .accessibilityIdentifier("planRemove")
                }
            }
        }
        .navigationTitle(request.title.prefix(1).uppercased() + request.title.dropFirst())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPicking) {
            MealPicker(title: request.title) { meal in
                MealPlan.plan(meal, day: entry.day, slot: entry.slot, context: context)
            }
            .presentationDetents([.medium, .large])
        }
        .onDisappear { try? context.save() }
    }

    private var servingsBinding: Binding<Int> {
        Binding(get: { entry.servings }, set: { MealPlan.setServings($0, of: entry) })
    }

    private func costText(_ planned: PlannedMeal) -> String {
        guard let cost = planned.cost else { return "No prices yet" }
        return planned.isComplete ? cost.formatted() : "At least \(cost.formatted())"
    }

    private func footer(meal: Meal, planned: PlannedMeal) -> String {
        let serves = meal.servings == 1 ? "1 serving" : "\(meal.servings) servings"
        let base = "\(meal.name) makes \(serves). The cost is scaled to \(entry.servings), at the cheapest prices you've seen in the last 90 days."
        guard planned.cost != nil else {
            return "None of its ingredients has a price yet. Pick them from things you've bought to get one."
        }
        return planned.isComplete ? base : base + " Some ingredients have no price, so it costs at least this."
    }
}
