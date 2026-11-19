import Foundation

// A week's plan as one shopping list (BACKLOG MEAL-003). Pure, so Android merges the same way.
// Fixture: `scanit-core/Fixtures/plan-list.json`.

/// One ingredient of a planned meal.
public struct PlanIngredient: Hashable, Codable, Sendable {
    public var text: String
    /// The GTIN when it was picked from past purchases.
    public var code: String?
    /// Packs the meal takes for its own servings.
    public var quantity: Int
    /// The user has it at home, so it stays off the list.
    public var inPantry: Bool

    public init(text: String, code: String?, quantity: Int, inPantry: Bool = false) {
        self.text = text
        self.code = code
        self.quantity = quantity
        self.inPantry = inPantry
    }

    /// Lines merge on this: the same product, or failing that the same words.
    public var key: String { PlanList.key(text: text, code: code) }
}

/// One planned meal with what goes into it.
public struct PlannedIngredients: Hashable, Codable, Sendable {
    public var meal: String
    public var mealServings: Int
    public var servings: Int
    public var ingredients: [PlanIngredient]

    public init(meal: String, mealServings: Int, servings: Int, ingredients: [PlanIngredient]) {
        self.meal = meal
        self.mealServings = mealServings
        self.servings = servings
        self.ingredients = ingredients
    }
}

/// One line the plan puts on the shopping list.
public struct PlanListLine: Hashable, Sendable, Identifiable {
    public let key: String
    /// The words of the first ingredient that asked for it.
    public let text: String
    public let code: String?
    /// Whole packs: the planned amounts added up exactly, then rounded up once.
    public let packs: Int
    /// The meals that need it, each once, in plan order.
    public let meals: [String]
    /// Any of its ingredients is marked as at home.
    public let inPantry: Bool

    public var id: String { key }
}

public enum PlanList {
    /// Merges the plan's ingredients into one line per product (or per wording, for typed ones), in
    /// the order they first appear. Each ingredient counts quantity × servings ÷ the meal's
    /// servings packs; a line's fractions are added exactly and rounded up once, because the till
    /// sells whole packs. Meals planned for no servings, and ingredients of no packs, add nothing.
    public static func lines(_ meals: [PlannedIngredients]) -> [PlanListLine] {
        struct Running {
            var text: String
            var code: String?
            var amount = Fraction.zero
            var meals: [String] = []
            var inPantry = false
        }
        var order: [String] = []
        var running: [String: Running] = [:]
        for meal in meals where meal.servings >= 1 && meal.mealServings >= 1 {
            for ingredient in meal.ingredients where ingredient.quantity >= 1 {
                let text = ingredient.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let key = ingredient.key
                if running[key] == nil {
                    order.append(key)
                    running[key] = Running(text: text, code: ingredient.code)
                }
                running[key]?.amount += Fraction(ingredient.quantity * meal.servings, meal.mealServings)
                if running[key]?.meals.contains(meal.meal) == false { running[key]?.meals.append(meal.meal) }
                if ingredient.inPantry { running[key]?.inPantry = true }
            }
        }
        return order.compactMap { key in
            running[key].map {
                PlanListLine(key: key, text: $0.text, code: $0.code, packs: $0.amount.ceiling, meals: $0.meals, inPantry: $0.inPantry)
            }
        }
    }

    /// `code:<gtin>` for a product, `text:<folded words>` for a typed ingredient, so "Fruta" and
    /// "frúta " are one line.
    public static func key(text: String, code: String?) -> String {
        if let code, !code.isEmpty { return "code:\(code)" }
        return "text:\(ChainCatalog.fold(text))"
    }
}

/// An exact non-negative fraction, so three thirds of a pack make one pack and not two.
private struct Fraction {
    var numerator: Int
    var denominator: Int

    static let zero = Fraction(0, 1)

    init(_ numerator: Int, _ denominator: Int) {
        let divisor = Self.gcd(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    static func += (lhs: inout Fraction, rhs: Fraction) {
        lhs = Fraction(lhs.numerator * rhs.denominator + rhs.numerator * lhs.denominator, lhs.denominator * rhs.denominator)
    }

    var ceiling: Int { (numerator + denominator - 1) / denominator }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (abs(a), abs(b))
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}
