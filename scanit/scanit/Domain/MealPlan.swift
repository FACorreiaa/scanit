import Foundation
import ScanItCore
import SwiftData

/// The meals of a day: lunch and dinner, the two that cost most to plan for. Stored as a raw
/// string so more can be added without a migration.
nonisolated enum PlanSlot: String, CaseIterable, Codable, Identifiable {
    case lunch, dinner

    var id: Self { self }

    var title: String {
        switch self {
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        }
    }
}

/// One meal put into one day's slot (BACKLOG MEAL-002). One meal per slot: planning another
/// replaces it.
@Model
nonisolated final class PlanEntry: SyncedRecord {
    @Attribute(.unique) var id: UUID
    /// The calendar day as `yyyy-MM-dd`: a day, not an instant, so travelling across time zones
    /// does not move the plan, and another device reads the same day.
    var day: String
    var slotRaw: String
    var meal: Meal?
    /// Servings planned for this day; starts at the meal's own.
    var servings: Int
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStateRaw: String

    init(day: String, slot: PlanSlot, servings: Int, now: Date = .now) {
        self.id = UUID()
        self.day = day
        self.slotRaw = slot.rawValue
        self.servings = servings
        self.createdAt = now
        self.updatedAt = now
        self.syncStateRaw = SyncState.dirty.rawValue
    }

    var slot: PlanSlot { PlanSlot(rawValue: slotRaw) ?? .dinner }

    /// Shown in the plan: not deleted, and its meal still exists.
    var isLive: Bool { deletedAt == nil && meal != nil && meal?.deletedAt == nil }
}

/// Seven calendar days, starting on the calendar's first weekday: the phone's setting, so the
/// week looks like the user's own calendar.
struct PlanWeek: Hashable {
    /// `yyyy-MM-dd` keys, in order.
    let days: [String]

    init(containing date: Date, calendar: Calendar = .current) {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        days = (0..<7).map { offset in
            Self.key(for: calendar.date(byAdding: .day, value: offset, to: start) ?? start, calendar: calendar)
        }
    }

    /// The week `weeks` weeks before (negative) or after this one.
    func shifted(by weeks: Int, calendar: Calendar = .current) -> PlanWeek {
        guard let first = days.first.flatMap({ Self.date(for: $0, calendar: calendar) }),
              let moved = calendar.date(byAdding: .day, value: 7 * weeks, to: first)
        else { return self }
        return PlanWeek(containing: moved, calendar: calendar)
    }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Noon on that day, so formatting it never slips into the day before or after.
    static func date(for key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}

/// The plan's rules, kept out of the views (the `MealBook` pattern).
enum MealPlan {
    static func entries(in week: PlanWeek, context: ModelContext) -> [PlanEntry] {
        let days = week.days
        let descriptor = FetchDescriptor<PlanEntry>(
            predicate: #Predicate { $0.deletedAt == nil && days.contains($0.day) },
            sortBy: [SortDescriptor(\.day), SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
    }

    /// Puts `meal` into a day's slot at the meal's own servings. A slot that already has a meal
    /// gets this one instead.
    @discardableResult
    static func plan(
        _ meal: Meal, day: String, slot: PlanSlot, context: ModelContext, now: Date = .now
    ) -> PlanEntry {
        let existing = liveEntries(day: day, slot: slot, context: context)
        if let entry = existing.first {
            // A second row in one slot can only come from another device; keep the first.
            for extra in existing.dropFirst() { extra.softDelete(now) }
            if entry.meal?.id != meal.id {
                entry.meal = meal
                entry.servings = meal.servings
                entry.touch(now)
            }
            try? context.save()
            return entry
        }
        let entry = PlanEntry(day: day, slot: slot, servings: meal.servings, now: now)
        context.insert(entry)
        entry.meal = meal
        try? context.save()
        return entry
    }

    static func setServings(_ servings: Int, of entry: PlanEntry, now: Date = .now) {
        let clamped = min(max(servings, MealBook.servingsRange.lowerBound), MealBook.servingsRange.upperBound)
        guard clamped != entry.servings else { return }
        entry.servings = clamped
        entry.touch(now)
    }

    static func remove(_ entry: PlanEntry, context: ModelContext, now: Date = .now) {
        entry.softDelete(now)
        try? context.save()
    }

    /// The entries of `source` whose slot is still empty in `target`, as they would land there.
    static func copyable(from source: PlanWeek, to target: PlanWeek, context: ModelContext) -> [(entry: PlanEntry, day: String)] {
        let filled = Set(entries(in: target, context: context).map { "\($0.day)/\($0.slotRaw)" })
        let dayMap = Dictionary(uniqueKeysWithValues: zip(source.days, target.days))
        return entries(in: source, context: context).compactMap { entry in
            guard let day = dayMap[entry.day], !filled.contains("\(day)/\(entry.slotRaw)") else { return nil }
            return (entry, day)
        }
    }

    /// "Copy last week": fills the empty slots of `target` from the same weekday and slot of
    /// `source`, with the same servings. Slots already planned are left alone. Returns how many
    /// meals were copied.
    @discardableResult
    static func copy(from source: PlanWeek, to target: PlanWeek, context: ModelContext, now: Date = .now) -> Int {
        let copies = copyable(from: source, to: target, context: context)
        for (entry, day) in copies {
            guard let meal = entry.meal else { continue }
            let copy = PlanEntry(day: day, slot: entry.slot, servings: entry.servings, now: now)
            context.insert(copy)
            copy.meal = meal
        }
        try? context.save()
        return copies.count
    }

    /// What a planned meal costs for its servings, from the meal's estimate.
    static func planned(_ entry: PlanEntry, estimate: MealCostEstimate) -> PlannedMeal {
        PlannedMeal(estimate: estimate, mealServings: entry.meal?.servings ?? 1, servings: entry.servings)
    }

    private static func liveEntries(day: String, slot: PlanSlot, context: ModelContext) -> [PlanEntry] {
        let slotRaw = slot.rawValue
        let descriptor = FetchDescriptor<PlanEntry>(
            predicate: #Predicate { $0.deletedAt == nil && $0.day == day && $0.slotRaw == slotRaw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
    }
}
