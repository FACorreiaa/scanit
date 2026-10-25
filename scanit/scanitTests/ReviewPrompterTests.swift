import Foundation
import Testing
@testable import scanit

/// The rating-ask rules, on a throwaway `UserDefaults` suite and a clock the test moves.
@MainActor
struct ReviewPrompterTests {
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
        func advance(days: Double) { now = now.addingTimeInterval(days * 24 * 60 * 60) }
        func advance(hours: Double) { now = now.addingTimeInterval(hours * 60 * 60) }
    }

    private let defaults: UserDefaults
    private let clock: Clock
    private let calendar: Calendar

    init() throws {
        let suite = "scanit.review.tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = calendar
        // Installed at 10:00 UTC, so "+1 day" always lands on a new calendar day.
        clock = Clock(try Date("2026-10-01T10:00:00Z", strategy: .iso8601))
    }

    private func prompter() -> ReviewPrompter {
        ReviewPrompter(defaults: defaults, calendar: calendar, now: { [clock] in clock.now })
    }

    @Test func asksAfterThreeSuccessesOnDifferentDays() {
        let reviews = prompter()
        clock.advance(days: 1)
        reviews.recordSuccess()
        clock.advance(days: 1)
        reviews.recordSuccess()
        #expect(!reviews.isPromptDue, "two days is not enough")
        clock.advance(days: 1)
        reviews.recordSuccess()
        #expect(reviews.successCount == 3)
        #expect(reviews.isPromptDue)
    }

    @Test func successesOnTheSameDayCountOnce() {
        let reviews = prompter()
        clock.advance(days: 2)
        reviews.recordSuccess()
        clock.advance(hours: 1)
        reviews.recordSuccess()
        clock.advance(hours: 1)
        reviews.recordSuccess()
        #expect(reviews.successCount == 1)
        #expect(!reviews.isPromptDue)
    }

    /// With one count per calendar day, three successes cannot fit in a fresh install's first
    /// 24 hours, so the grace only bites when the count is older than the first-seen stamp
    /// (written here directly). It still has to hold.
    @Test func firstDayGraceBlocksSuccesses() {
        defaults.set(2, forKey: "scanit.review.successCount")
        defaults.set(calendar.startOfDay(for: clock.now.addingTimeInterval(-86_400)), forKey: "scanit.review.lastCountedDay")
        let reviews = prompter() // first seen now
        clock.advance(hours: 1)
        reviews.recordSuccess()
        #expect(reviews.successCount == 3)
        #expect(!reviews.isPromptDue, "inside the first 24 hours")

        clock.advance(days: 1)
        reviews.recordSuccess()
        #expect(reviews.isPromptDue, "past the first day, the count earns the ask")
    }

    @Test func milestoneOnDayOneIsDue() {
        let reviews = prompter()
        reviews.recordMilestone(once: "firstTrip")
        #expect(reviews.isPromptDue)
    }

    @Test func onceKeyFiresOnlyOnce() {
        let reviews = prompter()
        reviews.recordMilestone(once: "firstTrip")
        #expect(reviews.isPromptDue)
        reviews.skipPrompt()
        reviews.recordMilestone(once: "firstTrip")
        #expect(!reviews.isPromptDue)

        // The key survives a relaunch.
        let relaunched = prompter()
        relaunched.recordMilestone(once: "firstTrip")
        #expect(!relaunched.isPromptDue)

        // A milestone without a key, or with another key, still asks.
        relaunched.recordMilestone()
        #expect(relaunched.isPromptDue)
    }

    @Test func cooldownBlocksSuccessesAndMilestones() {
        let reviews = prompter()
        clock.advance(days: 1)
        reviews.didPrompt()
        for _ in 0..<3 {
            clock.advance(days: 1)
            reviews.recordSuccess()
        }
        #expect(reviews.successCount == 3)
        #expect(!reviews.isPromptDue)
        reviews.recordMilestone(once: "firstTrip")
        #expect(!reviews.isPromptDue)
        reviews.recordMilestone()
        #expect(!reviews.isPromptDue)

        clock.advance(days: 120)
        reviews.recordMilestone()
        #expect(reviews.isPromptDue, "after 120 days the cooldown is over")
    }

    @Test func disabledBlocksSuccessesAndMilestones() {
        let reviews = prompter()
        reviews.isEnabled = false
        for _ in 0..<4 {
            clock.advance(days: 1)
            reviews.recordSuccess()
        }
        #expect(!reviews.isPromptDue)
        reviews.recordMilestone()
        #expect(!reviews.isPromptDue)
        #expect(!prompter().isEnabled, "the switch is persisted")

        reviews.recordMilestone(once: "firstTrip")
        reviews.isEnabled = true
        reviews.recordMilestone()
        #expect(reviews.isPromptDue)
        reviews.isEnabled = false
        #expect(!reviews.isPromptDue, "turning it off clears a pending ask")
    }

    @Test func didPromptResetsTheCount() {
        let reviews = prompter()
        for _ in 0..<3 {
            clock.advance(days: 1)
            reviews.recordSuccess()
        }
        #expect(reviews.isPromptDue)
        reviews.didPrompt()
        #expect(!reviews.isPromptDue)
        #expect(reviews.successCount == 0)
    }

    @Test func suppressedUnderUITestsNeverAsks() {
        let reviews = ReviewPrompter(defaults: defaults, calendar: calendar, now: { [clock] in clock.now }, isSuppressed: true)
        reviews.recordMilestone(once: "firstTrip")
        for _ in 0..<3 {
            clock.advance(days: 1)
            reviews.recordSuccess()
        }
        #expect(!reviews.isPromptDue)
    }
}
