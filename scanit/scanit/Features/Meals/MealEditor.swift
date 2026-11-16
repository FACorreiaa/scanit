import ScanItCore
import SwiftData
import SwiftUI

/// One meal: name, servings, what it costs, and its ingredients (BACKLOG MEAL-001). Cost comes
/// first because it is the reason to plan: an ingredient picked from past purchases is priced at
/// the cheapest price seen in the last 90 days, and the screen says where that was.
struct MealEditor: View {
    @Environment(\.modelContext) private var context
    @Bindable var meal: Meal
    let prices: [PriceSnapshot]
    let currency: String

    @State private var newText = ""
    @FocusState private var focus: Field?

    private enum Field { case name, ingredient, note }

    var body: some View {
        let estimate = MealBook.estimate(meal, prices: prices, currency: currency)
        let ingredients = meal.liveIngredients
        let suggestions = ShoppingList.suggestions(for: newText, context: context)

        Form {
            Section {
                TextField("Meal name", text: nameBinding)
                    .font(.title3)
                    .textInputAutocapitalization(.sentences)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .ingredient }
                    .accessibilityIdentifier("mealName")
                Stepper(value: servingsBinding, in: MealBook.servingsRange) {
                    Text("Serves \(meal.servings)")
                }
                .accessibilityIdentifier("mealServings")
            }

            costSection(estimate)

            Section {
                ForEach(Array(zip(ingredients, estimate.lines)), id: \.0.id) { ingredient, line in
                    IngredientRow(ingredient: ingredient, line: line)
                }
                .onDelete { offsets in
                    for index in offsets { MealBook.removeIngredient(ingredients[index], context: context) }
                }

                TextField("Add an ingredient", text: $newText)
                    .focused($focus, equals: .ingredient)
                    .submitLabel(.done)
                    .onSubmit { add(newText, code: nil) }
                    .accessibilityIdentifier("ingredientNew")
                ForEach(suggestions) { suggestion in
                    Button {
                        add(suggestion.name, code: suggestion.code)
                    } label: {
                        SuggestionLabel(suggestion: suggestion, price: cheapest(suggestion.code))
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("ingredientSuggestion")
                }
            } header: {
                Text("Ingredients")
            } footer: {
                Text("Pick from things you've bought before to get a price. Typed ingredients stay on the list without one.")
            }

            Section("Note") {
                TextField("Optional", text: noteBinding, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focus, equals: .note)
                    .accessibilityIdentifier("mealNote")
            }
        }
        .navigationTitle(meal.name.isEmpty ? "New meal" : meal.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if meal.name.isEmpty { focus = .name } }
        .onDisappear { MealBook.finishEditing(meal, context: context) }
    }

    // MARK: - Cost

    @ViewBuilder
    private func costSection(_ estimate: MealCostEstimate) -> some View {
        Section {
            if let perServing = estimate.perServing {
                LabeledContent("A serving") {
                    Text(perServing.formatted())
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .accessibilityIdentifier("mealCostPerServing")
                LabeledContent(estimate.isComplete ? "Whole meal" : "Whole meal, at least") {
                    Text(estimate.total.formatted()).monospacedDigit()
                }
                .accessibilityIdentifier("mealCostTotal")
            } else {
                Text("No prices yet")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mealCostNone")
            }
        } header: {
            Text("Cost")
        } footer: {
            Text(costFooter(estimate))
        }
    }

    private func costFooter(_ estimate: MealCostEstimate) -> String {
        let basis = "At the cheapest price you've seen for each in the last 90 days, in whole packs as the till charges them."
        switch estimate.unpricedLines {
        case 0: return basis
        case 1: return basis + " 1 ingredient has no price yet, so the meal costs more than this."
        default: return basis + " \(estimate.unpricedLines) ingredients have no price yet, so the meal costs more than this."
        }
    }

    private func cheapest(_ code: String) -> PriceSnapshot? {
        MealCost.estimate(
            ingredients: [IngredientSnapshot(code: code, quantity: 1)], servings: 1, prices: prices, currency: currency, now: .now
        ).lines.first?.price
    }

    // MARK: - Editing

    private var nameBinding: Binding<String> {
        Binding(get: { meal.name }, set: { value in
            meal.name = value
            meal.touch()
        })
    }

    private var servingsBinding: Binding<Int> {
        Binding(get: { meal.servings }, set: { value in MealBook.setServings(value, of: meal) })
    }

    private var noteBinding: Binding<String> {
        Binding(get: { meal.note ?? "" }, set: { value in
            meal.note = value.isEmpty ? nil : value
            meal.touch()
        })
    }

    /// Adds and keeps the field ready for the next one. Submitting an empty field means "done
    /// adding", so the keyboard goes and the cost above is in view again.
    private func add(_ text: String, code: String?) {
        guard MealBook.addIngredient(text, code: code, to: meal, context: context) != nil else {
            focus = nil
            return
        }
        newText = ""
        focus = .ingredient
    }
}

/// An ingredient on two lines: its name and what it adds to the meal, then where that price was
/// seen and the packs. The pack price shows only when there is more than one pack, so a single
/// pack never repeats the same amount twice.
private struct IngredientRow: View {
    let ingredient: MealIngredient
    let line: IngredientPrice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ingredient.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let total = line.lineTotal {
                    Text(total.formatted()).monospacedDigit()
                }
            }
            HStack(spacing: 12) {
                Text(priceText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Stepper(value: quantityBinding, in: MealBook.quantityRange) {
                    Text("× \(ingredient.quantity)").monospacedDigit()
                }
                .fixedSize()
                .accessibilityLabel("Packs of \(ingredient.text)")
                .accessibilityValue("\(ingredient.quantity)")
            }
        }
        .padding(.vertical, 2)
        // One container per row (the stepper stays reachable inside it); without this the
        // identifier lands on every child.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ingredientRow")
    }

    private var priceText: String {
        guard let price = line.price else {
            return ingredient.code == nil ? "Typed, no price" : "No price in the last 90 days"
        }
        let seen = "at \(price.storeName ?? "a store") · \(price.observedAt.formatted(.dateTime.day().month(.abbreviated)))"
        guard ingredient.quantity > 1 else { return seen }
        return "\(Money(amountMinor: price.priceMinor, currency: price.currency).formatted()) each \(seen)"
    }

    private var quantityBinding: Binding<Int> {
        Binding(get: { ingredient.quantity }, set: { value in
            MealBook.setQuantity(value, of: ingredient)
            ingredient.meal?.touch()
        })
    }
}

/// A past purchase offered while typing, with its cheapest recent price so the cheaper of two
/// similar products is easy to pick.
private struct SuggestionLabel: View {
    let suggestion: ListSuggestion
    let price: PriceSnapshot?

    var body: some View {
        HStack {
            Label(suggestion.name, systemImage: "clock.arrow.circlepath")
            Spacer(minLength: 8)
            if let price {
                Text(Money(amountMinor: price.priceMinor, currency: price.currency).formatted())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
