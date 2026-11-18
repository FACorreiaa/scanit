import ScanItCore
import SwiftData
import SwiftUI

/// Picks a meal for one day's slot. Each meal shows its cost a serving, so the cheaper choice is
/// in view while choosing. A meal can be made here when the one wanted is not there yet.
struct MealPicker: View {
    let title: String
    let onPick: (Meal) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Meal> { $0.deletedAt == nil }, sort: \Meal.name)
    private var meals: [Meal]
    @State private var path: [Meal] = []

    var body: some View {
        let prices = InsightsSource.prices(context: context)
        let currency = InsightsSource.homeCurrency(context: context)

        NavigationStack(path: $path) {
            List(meals, id: \.id) { meal in
                Button {
                    onPick(meal)
                    dismiss()
                } label: {
                    MealRow(meal: meal, estimate: MealBook.estimate(meal, prices: prices, currency: currency))
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("mealPick")
            }
            .overlay {
                if meals.isEmpty {
                    ContentUnavailableView {
                        Label("No meals yet", systemImage: "fork.knife")
                    } description: {
                        Text("Make a meal from things you've bought before, then put it into your week.")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Meal.self) { meal in
                MealEditor(meal: meal, prices: prices, currency: currency)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("mealPickCancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionBar(title: "New meal", identifier: "pickerNewMeal") {
                    path.append(MealBook.create(context: context))
                }
            }
        }
    }
}
