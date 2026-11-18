import Foundation
import ScanItCore
import SwiftData

/// One line of the shopping list (BACKLOG ADD-005): what to get on the next trip. A line picked
/// from past purchases carries that product's code; a typed one is words only.
@Model
nonisolated final class ListItem: SyncedRecord {
    @Attribute(.unique) var id: UUID
    var text: String
    /// The GTIN of a product bought before, when the line was picked from a suggestion.
    var code: String?
    /// Packs to get (MEAL-003: a planned week can need 2 of the same). A default, so stores from
    /// before it open without a migration.
    var quantity: Int = 1
    var doneAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var syncStateRaw: String

    init(text: String, code: String? = nil, quantity: Int = 1, now: Date = .now) {
        self.id = UUID()
        self.text = text
        self.code = code
        self.quantity = max(quantity, 1)
        self.createdAt = now
        self.updatedAt = now
        self.syncStateRaw = SyncState.dirty.rawValue
    }

    var isDone: Bool { doneAt != nil }
}

/// A product bought before, offered while a line is being typed.
struct ListSuggestion: Identifiable, Equatable {
    let code: String
    let name: String
    var id: String { code }
}

/// The list's rules, kept out of the views: adding, ticking by hand, and ticking by scan.
enum ShoppingList {
    static func lines(context: ModelContext) -> [ListItem] {
        let descriptor = FetchDescriptor<ListItem>(
            predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Adds a line. Blank text is ignored, and so is a line already waiting on the list.
    @discardableResult
    static func add(_ text: String, code: String? = nil, context: ModelContext, now: Date = .now) -> ListItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let waiting = lines(context: context).filter { !$0.isDone }
        if waiting.contains(where: { fold($0.text) == fold(trimmed) || (code != nil && $0.code == code) }) { return nil }
        let line = ListItem(text: trimmed, code: code, now: now)
        context.insert(line)
        try? context.save()
        return line
    }

    /// Puts `quantity` packs on the list. A line already waiting for the same product or words
    /// is raised to `quantity` if it asks for fewer, never added to, so adding the same week twice
    /// does not double it. Returns the line, new or raised; `nil` for blank text.
    @discardableResult
    static func merge(
        _ text: String, code: String?, quantity: Int, context: ModelContext, now: Date = .now
    ) -> ListItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let waiting = lines(context: context).filter { !$0.isDone }
        if let existing = waiting.first(where: { (code != nil && $0.code == code) || fold($0.text) == fold(trimmed) }) {
            if existing.quantity < quantity {
                existing.quantity = quantity
                existing.touch(now)
                try? context.save()
            }
            return existing
        }
        guard let line = add(trimmed, code: code, context: context, now: now) else { return nil }
        line.quantity = max(quantity, 1)
        try? context.save()
        return line
    }

    static func toggle(_ line: ListItem, context: ModelContext, now: Date = .now) {
        line.doneAt = line.isDone ? nil : now
        line.touch(now)
        try? context.save()
    }

    static func remove(_ line: ListItem, context: ModelContext, now: Date = .now) {
        line.softDelete(now)
        try? context.save()
    }

    /// Ticked lines leave the list: after a finished trip, or from "Clear ticked".
    static func clearDone(context: ModelContext, now: Date = .now) {
        for line in lines(context: context) where line.isDone { line.softDelete(now) }
        try? context.save()
    }

    /// Ticks the line a scanned product answers: the same code, or failing that a typed line whose
    /// words all start a word of the product's name. One line per scan, the oldest first.
    @discardableResult
    static func tick(code: String, name: String?, context: ModelContext, now: Date = .now) -> ListItem? {
        let waiting = lines(context: context).filter { !$0.isDone }
        let match = waiting.first { $0.code == code }
            ?? name.flatMap { name in waiting.first { $0.code == nil && matches(line: $0.text, productName: name) } }
        guard let match else { return nil }
        match.doneAt = now
        match.touch(now)
        try? context.save()
        return match
    }

    /// "leite" answers "Leite meio gordo · Mimosa"; "pao forma" answers "Pão de forma". Words of
    /// one or two letters are too loose to match on.
    static func matches(line: String, productName: String) -> Bool {
        let wanted = words(line).filter { $0.count >= 3 }
        guard !wanted.isEmpty else { return false }
        let have = words(productName)
        return wanted.allSatisfy { word in have.contains { $0.hasPrefix(word) } }
    }

    /// Products bought before whose name contains what is being typed, most recent first.
    static func suggestions(for text: String, context: ModelContext, limit: Int = 5) -> [ListSuggestion] {
        let typed = fold(text)
        guard typed.count >= 2 else { return [] }
        let gtin = ScannedCode.Kind.gtin.rawValue
        let descriptor = FetchDescriptor<CartItem>(
            predicate: #Predicate { $0.productName != nil && $0.codeKindRaw == gtin && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.scannedAt, order: .reverse)]
        )
        var seen: Set<String> = []
        var found: [ListSuggestion] = []
        for item in (try? context.fetch(descriptor)) ?? [] {
            guard let name = item.productName, !item.scannedCode.isInStore,
                  fold(name).contains(typed), seen.insert(item.code).inserted
            else { continue }
            found.append(ListSuggestion(code: item.code, name: name))
            if found.count == limit { break }
        }
        return found
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ text: String) -> [String] {
        fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
