import Foundation
import Observation
import ScanItCore

/// Monthly grocery budgets, one per currency (BACKLOG ADD-003, BUD-001). Kept in `UserDefaults`:
/// they are preferences, not trip data, so they are not part of the synced model. Currencies are
/// never converted, so a € budget only ever measures € trips.
@Observable
final class BudgetStore {
    /// Budget per ISO 4217 code (upper case).
    private(set) var budgets: [String: Money] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    private static let budgetsKey = "monthlyBudgets"
    // ADD-003 stored a single budget under these two keys; they are moved on first launch.
    private static let legacyMinorKey = "monthlyBudget.minor"
    private static let legacyCurrencyKey = "monthlyBudget.currency"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.budgetsKey) as? [String: Int] ?? [:]
        for (currency, minor) in stored where minor > 0 {
            budgets[currency] = Money(amountMinor: minor, currency: currency)
        }
        migrateLegacyBudget()
    }

    /// Currencies that have a budget, sorted.
    var currencies: [String] { budgets.keys.sorted() }

    func budget(for currency: String) -> Money? {
        budgets[currency.uppercased()]
    }

    /// Sets the budget for `money.currency`; zero or less removes it.
    func set(_ money: Money) {
        let currency = money.currency.uppercased()
        budgets[currency] = money.amountMinor > 0 ? Money(amountMinor: money.amountMinor, currency: currency) : nil
        save()
    }

    func remove(currency: String) {
        budgets[currency.uppercased()] = nil
        save()
    }

    /// The month so far against the budget in the same currency, with the same near and over
    /// thresholds as a trip limit. `nil` when that currency has no budget.
    func status(spent: Money) -> LimitStatus? {
        guard let budget = budget(for: spent.currency) else { return nil }
        return LimitStatus(totalMinor: spent.amountMinor, limitMinor: budget.amountMinor)
    }

    private func save() {
        defaults.set(budgets.mapValues(\.amountMinor), forKey: Self.budgetsKey)
    }

    private func migrateLegacyBudget() {
        guard defaults.object(forKey: Self.legacyMinorKey) != nil else { return }
        let minor = defaults.integer(forKey: Self.legacyMinorKey)
        if minor > 0, let currency = defaults.string(forKey: Self.legacyCurrencyKey)?.uppercased(),
           budgets[currency] == nil {
            budgets[currency] = Money(amountMinor: minor, currency: currency)
            save()
        }
        defaults.removeObject(forKey: Self.legacyMinorKey)
        defaults.removeObject(forKey: Self.legacyCurrencyKey)
    }
}
