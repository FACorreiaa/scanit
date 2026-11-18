import Foundation

// What a week of planned meals costs (BACKLOG MEAL-002). Pure, so Android and the server add it
// up the same way. Fixture: `scanit-core/Fixtures/plan-cost.json`.

/// One meal put into the plan, as the week's cost needs it.
public struct PlannedMeal: Hashable, Codable, Sendable {
    /// The meal's cost for the servings it makes (`MealCostEstimate.total`). `nil` when none of
    /// its ingredients has a price.
    public var mealTotal: Money?
    /// Every ingredient is priced, so `mealTotal` is the whole meal and not a floor.
    public var isComplete: Bool
    /// The servings the meal makes.
    public var mealServings: Int
    /// The servings planned for this day and slot.
    public var servings: Int

    public init(mealTotal: Money?, isComplete: Bool, mealServings: Int, servings: Int) {
        self.mealTotal = mealTotal
        self.isComplete = isComplete
        self.mealServings = mealServings
        self.servings = servings
    }

    public init(estimate: MealCostEstimate, mealServings: Int, servings: Int) {
        self.init(
            mealTotal: estimate.pricedLines > 0 ? estimate.total : nil, isComplete: estimate.isComplete,
            mealServings: mealServings, servings: servings
        )
    }

    /// The meal's cost scaled to the planned servings: total × servings ÷ the meal's servings,
    /// rounded half up. `nil` when nothing is priced or either count is below 1.
    public var cost: Money? {
        guard let mealTotal, mealServings >= 1, servings >= 1 else { return nil }
        let scaled = (mealTotal.amountMinor * servings + mealServings / 2) / mealServings
        return Money(amountMinor: scaled, currency: mealTotal.currency)
    }
}

public struct PlanCostSummary: Hashable, Sendable {
    /// The sum of each planned meal's rounded `cost`, so the rows on screen add up to it.
    public let total: Money
    public let meals: Int
    /// Meals with at least one priced ingredient.
    public let pricedMeals: Int
    /// Meals with every ingredient priced.
    public let completeMeals: Int

    /// Meals with no price at all: they add nothing to `total`.
    public var unpricedMeals: Int { meals - pricedMeals }
    /// Every planned meal is fully priced, so `total` is the week and not a floor.
    public var isComplete: Bool { meals > 0 && completeMeals == meals }
}

public enum PlanCost {
    /// Adds up the planned meals in `currency`. Never converts: a meal priced in another
    /// currency counts as unpriced.
    public static func summary(_ meals: [PlannedMeal], currency: String) -> PlanCostSummary {
        let currency = currency.uppercased()
        let costs = meals.map { meal in meal.cost.flatMap { $0.currency.uppercased() == currency ? $0 : nil } }
        let priced = costs.compactMap(\.self)
        let complete = zip(meals, costs).count { meal, cost in cost != nil && meal.isComplete }
        return PlanCostSummary(
            total: Money(amountMinor: priced.reduce(0) { $0 + $1.amountMinor }, currency: currency),
            meals: meals.count, pricedMeals: priced.count, completeMeals: complete
        )
    }
}
