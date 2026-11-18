import Foundation
import ScanItCore
import SwiftData

/// A meal the user cooks (BACKLOG MEAL-001): a name, how many it feeds, and its ingredients. The
/// point is cost: each meal is priced from what the user has scanned (`MealCost`), so planning a
/// week (MEAL-002, `MealPlan`) can show what it will cost and where it is cheapest (MEAL-004).
@Model
nonisolated final class Meal: SyncedRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var servings: Int
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStateRaw: String

    @Relationship(deleteRule: .cascade, inverse: \MealIngredient.meal)
    var ingredients: [MealIngredient] = []

    /// Days this meal is planned for (MEAL-002).
    @Relationship(deleteRule: .nullify, inverse: \PlanEntry.meal)
    var planEntries: [PlanEntry] = []

    init(name: String, servings: Int = 2, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.servings = servings
        self.createdAt = now
        self.updatedAt = now
        self.syncStateRaw = SyncState.dirty.rawValue
    }

    /// Ingredients not deleted, in the order they were added.
    var liveIngredients: [MealIngredient] {
        ingredients.filter { $0.deletedAt == nil }.sorted { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }
    }
}

/// One ingredient. Picked from past purchases it carries the product's code, which is what lets
/// the meal be priced; a typed one is words only.
@Model
nonisolated final class MealIngredient: SyncedRecord {
    @Attribute(.unique) var id: UUID
    var meal: Meal?
    var text: String
    /// The GTIN of a product bought before, when picked from a suggestion.
    var code: String?
    /// Packs the meal takes, as bought: the till charges whole packs.
    var quantity: Int
    /// Kept at home (MEAL-003), so "Add to list" leaves it off. A default, so stores from before
    /// it open without a migration.
    var inPantry: Bool = false
    var position: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStateRaw: String

    init(text: String, code: String? = nil, quantity: Int = 1, position: Int, now: Date = .now) {
        self.id = UUID()
        self.text = text
        self.code = code
        self.quantity = quantity
        self.position = position
        self.createdAt = now
        self.updatedAt = now
        self.syncStateRaw = SyncState.dirty.rawValue
    }
}

/// The meals' rules, kept out of the views (the `ShoppingList` pattern).
enum MealBook {
    static let servingsRange = 1...12
    static let quantityRange = 1...20

    static func meals(context: ModelContext) -> [Meal] {
        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// A new, empty meal. The editor discards it again if it is left with nothing in it.
    static func create(context: ModelContext, now: Date = .now) -> Meal {
        let meal = Meal(name: "", now: now)
        context.insert(meal)
        return meal
    }

    /// Adds an ingredient. Blank text is ignored. The same product, or the same words, already in
    /// the meal gets one more pack instead of a second line.
    @discardableResult
    static func addIngredient(
        _ text: String, code: String? = nil, to meal: Meal, context: ModelContext, now: Date = .now
    ) -> MealIngredient? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let live = meal.liveIngredients
        if let existing = live.first(where: { (code != nil && $0.code == code) || fold($0.text) == fold(trimmed) }) {
            setQuantity(existing.quantity + 1, of: existing, now: now)
            meal.touch(now)
            try? context.save()
            return existing
        }
        let ingredient = MealIngredient(
            text: trimmed, code: code, position: (live.map(\.position).max() ?? -1) + 1, now: now
        )
        context.insert(ingredient)
        ingredient.meal = meal
        meal.touch(now)
        try? context.save()
        return ingredient
    }

    static func setQuantity(_ quantity: Int, of ingredient: MealIngredient, now: Date = .now) {
        let clamped = min(max(quantity, quantityRange.lowerBound), quantityRange.upperBound)
        guard clamped != ingredient.quantity else { return }
        ingredient.quantity = clamped
        ingredient.touch(now)
    }

    static func setServings(_ servings: Int, of meal: Meal, now: Date = .now) {
        let clamped = min(max(servings, servingsRange.lowerBound), servingsRange.upperBound)
        guard clamped != meal.servings else { return }
        meal.servings = clamped
        meal.touch(now)
    }

    static func removeIngredient(_ ingredient: MealIngredient, context: ModelContext, now: Date = .now) {
        ingredient.softDelete(now)
        ingredient.meal?.touch(now)
        try? context.save()
    }

    /// Soft delete, with its ingredients and the days it was planned for, so sync (P4) can pass
    /// the deletion on.
    static func delete(_ meal: Meal, context: ModelContext, now: Date = .now) {
        for ingredient in meal.liveIngredients { ingredient.softDelete(now) }
        for entry in meal.planEntries where entry.deletedAt == nil { entry.softDelete(now) }
        meal.softDelete(now)
        try? context.save()
    }

    /// When the editor closes: a meal with no name and no ingredients was never really made, so it
    /// is removed outright (it was never synced). One with ingredients but no name gets a name.
    static func finishEditing(_ meal: Meal, context: ModelContext, now: Date = .now) {
        guard meal.deletedAt == nil else { return }
        let name = meal.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty && meal.liveIngredients.isEmpty {
            for ingredient in meal.ingredients { context.delete(ingredient) }
            context.delete(meal)
        } else if name.isEmpty {
            meal.name = "Untitled meal"
            meal.touch(now)
        } else if name != meal.name {
            meal.name = name
            meal.touch(now)
        }
        try? context.save()
    }

    /// What the meal costs at the cheapest prices the user has seen recently.
    static func estimate(_ meal: Meal, prices: [PriceSnapshot], currency: String, now: Date = .now) -> MealCostEstimate {
        MealCost.estimate(
            ingredients: meal.liveIngredients.map { IngredientSnapshot(code: $0.code, quantity: $0.quantity) },
            servings: meal.servings, prices: prices, currency: currency, now: now
        )
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
