import Foundation
import Observation
import ScanItCore

/// The monthly grocery budget (BACKLOG ADD-003). One amount for every month, kept in
/// `UserDefaults`: it is a preference, not trip data, so it is not part of the synced model.
@Observable
final class BudgetStore {
    private(set) var budget: Money?

    @ObservationIgnored private let defaults: UserDefaults
    private static let minorKey = "monthlyBudget.minor"
    private static let currencyKey = "monthlyBudget.currency"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let minor = defaults.integer(forKey: Self.minorKey)
        if minor > 0, let currency = defaults.string(forKey: Self.currencyKey) {
            budget = Money(amountMinor: minor, currency: currency)
        }
    }

    /// `nil`, zero or less removes the budget.
    func set(_ money: Money?) {
        guard let money, money.amountMinor > 0 else {
            budget = nil
            defaults.removeObject(forKey: Self.minorKey)
            defaults.removeObject(forKey: Self.currencyKey)
            return
        }
        budget = money
        defaults.set(money.amountMinor, forKey: Self.minorKey)
        defaults.set(money.currency, forKey: Self.currencyKey)
    }

    /// The month so far against the budget, with the same near and over thresholds as a trip
    /// limit. `nil` without a budget, or when it is in another currency than the spending.
    func status(spent: Money) -> LimitStatus? {
        guard let budget, budget.currency == spent.currency else { return nil }
        return LimitStatus(totalMinor: spent.amountMinor, limitMinor: budget.amountMinor)
    }
}
