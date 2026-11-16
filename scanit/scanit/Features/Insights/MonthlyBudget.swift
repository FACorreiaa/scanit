import ScanItCore
import SwiftUI

/// This month's spending against the monthly budget in one currency, or the way to set one
/// (BACKLOG ADD-003, BUD-001). Looks and behaves like a trip limit, so amber and red mean the same
/// thing everywhere.
struct MonthlyBudgetRow: View {
    @Environment(BudgetStore.self) private var budgets
    /// Finished trips this calendar month, in this row's currency.
    let spent: Money
    /// The Insights currency's row keeps the plain identifier; other currencies get a suffix.
    var isPrimary = true
    /// With budgets in more than one currency, each row names its currency.
    var showsCurrency = false

    @State private var isEditing = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            if let budget = budgets.budget(for: spent.currency), let status = budgets.status(spent: spent) {
                VStack(alignment: .leading, spacing: 2) {
                    if showsCurrency {
                        Text(spent.currency).font(.caption).foregroundStyle(.secondary)
                    }
                    TripTotalHeader(total: spent, limit: budget, status: status, compact: true)
                }
                .padding(.vertical, 8)
            } else {
                Label(showsCurrency ? "Set a monthly budget in \(spent.currency)" : "Set a monthly budget",
                      systemImage: "calendar.badge.plus")
            }
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier(isPrimary ? "monthlyBudget" : "monthlyBudget.\(spent.currency)")
        .accessibilityHint(budgets.budget(for: spent.currency) == nil ? "" : "Changes the monthly budget")
        .sheet(isPresented: $isEditing) {
            MonthlyBudgetSheet(currency: spent.currency)
                .presentationDetents([.medium])
        }
    }
}

private struct MonthlyBudgetSheet: View {
    @Environment(BudgetStore.self) private var budgets
    @Environment(\.dismiss) private var dismiss
    let currency: String

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(Money.symbol(for: currency)).foregroundStyle(.secondary)
                        TextField("0", text: $text)
                            .keyboardType(.decimalPad)
                            .focused($isFocused)
                            .font(.title3)
                            .monospacedDigit()
                            .accessibilityIdentifier("budgetAmount")
                    }
                } footer: {
                    Text("For groceries each calendar month. Finished trips count towards it.")
                }

                if budgets.budget(for: currency) != nil {
                    Section {
                        Button("Remove budget", role: .destructive) {
                            budgets.remove(currency: currency)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Monthly budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let amount { budgets.set(amount) }
                        dismiss()
                    }
                    .disabled(amount == nil)
                    .accessibilityIdentifier("saveBudget")
                }
            }
        }
        .onAppear {
            if let budget = budgets.budget(for: currency) {
                text = MoneyInput.editingText(budget)
            }
            isFocused = true
        }
    }

    private var amount: Money? {
        MoneyInput.parse(text, currency: currency).flatMap { $0.amountMinor > 0 ? $0 : nil }
    }
}
