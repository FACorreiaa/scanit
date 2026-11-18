import ScanItCore
import SwiftData
import SwiftUI

/// The Plan tab (BACKLOG MEAL-002): a week of lunches and dinners, and what the week costs at the
/// cheapest prices the user has seen. The cost is on top because saving is why the user plans.
struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<PlanEntry> { $0.deletedAt == nil })
    private var allEntries: [PlanEntry]
    // Read so the week's cost redraws when a meal or its ingredients change.
    @Query(filter: #Predicate<Meal> { $0.deletedAt == nil })
    private var meals: [Meal]

    @State private var weekOffset = 0
    @State private var picking: SlotRequest?
    @State private var showsMeals = false

    var body: some View {
        let calendar = Calendar.current
        let week = PlanWeek(containing: .now, calendar: calendar).shifted(by: weekOffset, calendar: calendar)
        let lastWeek = week.shifted(by: -1, calendar: calendar)
        let entries = allEntries.filter { $0.isLive && week.days.contains($0.day) }
        let prices = InsightsSource.prices(context: context)
        let currency = InsightsSource.homeCurrency(context: context)
        let costs = Self.costs(of: entries, prices: prices, currency: currency)
        let summary = PlanCost.summary(entries.compactMap { costs[$0.id] }, currency: currency)
        let copyable = MealPlan.copyable(from: lastWeek, to: week, context: context).count
        let today = PlanWeek.key(for: .now, calendar: calendar)

        NavigationStack {
            List {
                Section {
                    WeekSwitcher(week: week, offset: $weekOffset)
                    WeekCost(summary: summary, hasMeals: !meals.isEmpty)
                    WeekActions(mealCount: meals.count, copyable: copyable) {
                        showsMeals = true
                    } copy: {
                        withAnimation { _ = MealPlan.copy(from: lastWeek, to: week, context: context) }
                    }
                }

                ForEach(week.days, id: \.self) { day in
                    Section {
                        ForEach(PlanSlot.allCases) { slot in
                            if let entry = entries.first(where: { $0.day == day && $0.slot == slot }) {
                                NavigationLink(value: entry) {
                                    PlanEntryRow(entry: entry, cost: costs[entry.id])
                                }
                                .swipeActions {
                                    Button("Remove", systemImage: "trash", role: .destructive) {
                                        MealPlan.remove(entry, context: context)
                                    }
                                }
                            } else {
                                Button {
                                    picking = SlotRequest(day: day, slot: slot)
                                } label: {
                                    EmptySlotRow(slot: slot)
                                }
                                .accessibilityIdentifier("planAddSlot")
                            }
                        }
                    } header: {
                        DayHeader(day: day, isToday: day == today)
                    }
                }
            }
            // The hidden bar leaves no scroll edge effect, so the list needs a backdrop under the clock.
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background { Color(.systemGroupedBackground).ignoresSafeArea(edges: .top) }
            }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: PlanEntry.self) { entry in
                PlanEntryEditor(entry: entry, prices: prices, currency: currency)
            }
            .sheet(item: $picking) { request in
                MealPicker(title: request.title) { meal in
                    MealPlan.plan(meal, day: request.day, slot: request.slot, context: context)
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showsMeals) {
                MealsSheet()
                    .presentationDetents([.large])
            }
        }
    }

    /// Each planned meal's cost, estimating every meal once however often it is planned.
    private static func costs(
        of entries: [PlanEntry], prices: [PriceSnapshot], currency: String
    ) -> [UUID: PlannedMeal] {
        var estimates: [UUID: MealCostEstimate] = [:]
        var costs: [UUID: PlannedMeal] = [:]
        for entry in entries {
            guard let meal = entry.meal else { continue }
            let estimate = estimates[meal.id] ?? MealBook.estimate(meal, prices: prices, currency: currency)
            estimates[meal.id] = estimate
            costs[entry.id] = MealPlan.planned(entry, estimate: estimate)
        }
        return costs
    }
}

/// An empty slot the user tapped: which day and which meal of it.
struct SlotRequest: Identifiable {
    let day: String
    let slot: PlanSlot
    var id: String { "\(day)/\(slot.rawValue)" }

    /// "Wednesday lunch".
    var title: String {
        let weekday = PlanWeek.date(for: day)?.formatted(.dateTime.weekday(.wide)) ?? day
        return "\(weekday) \(slot.title.lowercased())"
    }
}

/// "This week · 16–22 Nov", with arrows to the weeks before and after.
private struct WeekSwitcher: View {
    let week: PlanWeek
    @Binding var offset: Int

    var body: some View {
        HStack {
            Button("Previous week", systemImage: "chevron.left") { offset -= 1 }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("planPreviousWeek")
            Spacer()
            VStack(spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(range)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Next week", systemImage: "chevron.right") { offset += 1 }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("planNextWeek")
        }
        // Two buttons in one row: each takes its own taps instead of the row taking both.
        .buttonStyle(.borderless)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .imageScale(.large)
    }

    private var title: String {
        switch offset {
        case 0: "This week"
        case 1: "Next week"
        case -1: "Last week"
        default: range
        }
    }

    private var range: String {
        let dates = [week.days.first, week.days.last].compactMap { $0.flatMap { PlanWeek.date(for: $0) } }
        guard let first = dates.first, let last = dates.last else { return "" }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return "\(first.formatted(style)) – \(last.formatted(style))"
    }
}

/// What the week costs, or what is missing for a price.
private struct WeekCost: View {
    let summary: PlanCostSummary
    let hasMeals: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headline)
                .font(.title.bold())
                .monospacedDigit()
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planWeekTotal")
    }

    private var headline: String {
        if summary.meals == 0 { return "Nothing planned" }
        if summary.pricedMeals == 0 { return "No prices yet" }
        return summary.isComplete ? summary.total.formatted() : "At least \(summary.total.formatted())"
    }

    private var caption: String {
        guard summary.meals > 0 else {
            return hasMeals
                ? "Put meals into days to see what the week costs."
                : "Save the meals you cook, then put them into days to see what the week costs."
        }
        let meals = summary.meals == 1 ? "1 meal" : "\(summary.meals) meals"
        let missing = summary.meals - summary.completeMeals
        guard missing > 0 else { return "\(meals), at the cheapest prices you've seen." }
        let some = missing == 1 ? "1 has" : "\(missing) have"
        return "\(meals). \(some) ingredients without a price."
    }
}

/// "Meals · 4" and "Copy last week".
private struct WeekActions: View {
    let mealCount: Int
    let copyable: Int
    let meals: () -> Void
    let copy: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { buttons }
            VStack(alignment: .leading, spacing: 12) { buttons }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder private var buttons: some View {
        Button(action: meals) {
            Label(mealCount == 0 ? "Meals" : "Meals · \(mealCount)", systemImage: "fork.knife")
        }
        .accessibilityIdentifier("planMeals")
        if copyable > 0 {
            Button(action: copy) {
                Label(copyable == 1 ? "Copy 1 from last week" : "Copy \(copyable) from last week",
                      systemImage: "arrow.uturn.forward")
            }
            .accessibilityIdentifier("planCopyLastWeek")
        }
    }
}

private struct DayHeader: View {
    let day: String
    let isToday: Bool

    var body: some View {
        let date = PlanWeek.date(for: day)?.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) ?? day
        Text(isToday ? "\(date) · Today" : date)
            .fontWeight(isToday ? .semibold : nil)
    }
}

private struct PlanEntryRow: View {
    let entry: PlanEntry
    let cost: PlannedMeal?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.slot.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.meal?.name ?? "")
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(costText)
                    .font(cost?.cost == nil ? .footnote : .body)
                    .foregroundStyle(cost?.cost == nil ? .secondary : .primary)
                    .monospacedDigit()
                Text("For \(entry.servings)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planEntry")
    }

    private var costText: String {
        guard let cost, let money = cost.cost else { return "No prices yet" }
        return cost.isComplete ? money.formatted() : "at least \(money.formatted())"
    }
}

private struct EmptySlotRow: View {
    let slot: PlanSlot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Plain grey: inside a button `.secondary` would take the tint.
            Text(slot.title)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))
            Label("Add a meal", systemImage: "plus.circle")
                .foregroundStyle(.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Add \(slot.title.lowercased())")
    }
}

#Preview {
    let container = try! ScanItSchema.container(inMemory: true)
    DemoData.seed(container.mainContext)
    DemoData.seedMeals(container.mainContext)
    return PlanView()
        .modelContainer(container)
}
