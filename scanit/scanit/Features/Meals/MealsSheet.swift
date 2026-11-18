import ScanItCore
import SwiftData
import SwiftUI

/// The meals the user cooks, each with what it costs at the prices they have seen (BACKLOG
/// MEAL-001). Opened from the Plan tab, whose week (MEAL-002) is made of these.
struct MealsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Meal> { $0.deletedAt == nil }, sort: \Meal.name)
    private var meals: [Meal]

    @State private var path: [Meal] = []
    @State private var order: Order = .name

    enum Order: String, CaseIterable, Identifiable {
        case name = "Name"
        case costPerServing = "Cost a serving"
        var id: Self { self }
    }

    var body: some View {
        // Read once per redraw and shared by every row and the editor.
        let prices = InsightsSource.prices(context: context)
        let currency = InsightsSource.homeCurrency(context: context)
        let rows = meals.map { (meal: $0, estimate: MealBook.estimate($0, prices: prices, currency: currency)) }

        NavigationStack(path: $path) {
            List {
                ForEach(sorted(rows), id: \.meal.id) { row in
                    NavigationLink(value: row.meal) {
                        MealRow(meal: row.meal, estimate: row.estimate)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            MealBook.delete(row.meal, context: context)
                        }
                    }
                }
            }
            .overlay {
                if meals.isEmpty {
                    ContentUnavailableView {
                        Label("No meals yet", systemImage: "fork.knife")
                    } description: {
                        Text("Save the meals you cook often. Pick ingredients you've scanned before and ScanItNow shows what each meal costs.")
                    }
                }
            }
            .navigationTitle("Meals")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Meal.self) { meal in
                MealEditor(meal: meal, prices: prices, currency: currency)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("mealsDone")
                }
                if meals.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Sort by", selection: $order) {
                                ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                        .accessibilityIdentifier("mealsSort")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionBar(title: "New meal", identifier: "newMeal") {
                    path.append(MealBook.create(context: context))
                }
            }
        }
    }

    /// Cheapest a serving first puts what saves most on top; meals without a price go last.
    private func sorted(_ rows: [(meal: Meal, estimate: MealCostEstimate)]) -> [(meal: Meal, estimate: MealCostEstimate)] {
        switch order {
        case .name:
            rows
        case .costPerServing:
            rows.sorted {
                ($0.estimate.perServing?.amountMinor ?? .max, $0.meal.name) < ($1.estimate.perServing?.amountMinor ?? .max, $1.meal.name)
            }
        }
    }
}

/// A meal with its cost a serving and in total; also the rows of `MealPicker`.
struct MealRow: View {
    let meal: Meal
    let estimate: MealCostEstimate

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name.isEmpty ? "Untitled meal" : meal.name)
                Text(details)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let perServing = estimate.perServing {
                    Text("\(perServing.formatted()) a serving")
                        .monospacedDigit()
                    Text(estimate.isComplete ? estimate.total.formatted() : "at least \(estimate.total.formatted())")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("No prices yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mealRow")
    }

    private var details: String {
        let count = meal.liveIngredients.count
        let ingredients = count == 1 ? "1 ingredient" : "\(count) ingredients"
        return "Serves \(meal.servings) · \(ingredients)"
    }
}
