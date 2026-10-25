import ScanItCore
import StoreKit
import SwiftData
import SwiftUI

/// Trip tab: the active trip, or an empty state with a big Start button. Owns the finish
/// summary because the active-trip screen disappears the moment the trip ends.
struct TripView: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(PurchaseStore.self) private var purchases
    @Environment(ReviewPrompter.self) private var reviews
    @Environment(\.analytics) private var analytics
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.paywallPolicy) private var paywall
    @Environment(\.modelContext) private var context
    @State private var isStarting = false
    @State private var finished: FinishedTrip?
    @State private var paywallReason: PaywallReasonItem?
    @State private var startAfterPaywall = false
    @Query(TripView.lastFinished) private var lastTrips: [ShoppingSession]

    private static var lastFinished: FetchDescriptor<ShoppingSession> {
        var descriptor = FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { $0.statusRaw == "finished" && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        NavigationStack {
            if let active = sessions.active {
                ActiveTripView(session: active) { finished = FinishedTrip(session: $0) }
            } else {
                ReadyToShop(lastTrip: lastTrips.first)
                    .safeAreaInset(edge: .bottom) {
                        PrimaryActionBar(title: "Start shopping", identifier: "openStartTrip", action: requestStart)
                    }
                    .toolbarVisibility(.hidden, for: .navigationBar)
            }
        }
        .sheet(isPresented: $isStarting) {
            StartTripSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $finished, onDismiss: summaryClosed) { trip in
            TripSummarySheet(session: trip.session)
        }
        // Open the start sheet only after the paywall has fully closed.
        .sheet(item: $paywallReason, onDismiss: {
            if startAfterPaywall {
                startAfterPaywall = false
                isStarting = true
            }
        }) { item in
            PaywallSheet(reason: item.reason) { startAfterPaywall = true }
                .presentationDetents([.medium, .large])
        }
        .task(id: reviews.isPromptDue) { await askForReviewIfDue() }
    }

    /// The summary closed. "Undo finish" puts the trip back as the active one; anything else
    /// (Done, swipe-down) keeps it, and a kept trip is the success worth a rating ask.
    private func summaryClosed() {
        guard sessions.active == nil else { return }
        reviews.recordSuccess()
        reviews.recordMilestone(once: "firstTrip")
    }

    /// Ask for a rating once the summary's dismissal has settled. Leaving the tab or the app
    /// first drops the ask; the count stands, so a later trip earns it again.
    private func askForReviewIfDue() async {
        guard reviews.isPromptDue else { return }
        try? await Task.sleep(for: ReviewPrompter.settleDelay)
        guard !Task.isCancelled, scenePhase == .active else {
            reviews.skipPrompt()
            return
        }
        guard reviews.isPromptDue else { return }
        requestReview()
        reviews.didPrompt()
        analytics.track(.reviewPromptRequested)
    }

    /// The free-trip quota is checked here and only here: a trip in progress always finishes.
    private func requestStart() {
        let abandoned = SessionStatus.abandoned.rawValue
        let started = (try? context.fetch(FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { $0.statusRaw != abandoned && $0.deletedAt == nil }
        )))?.map(\.startedAt) ?? []
        let used = PaywallPolicy.tripsCounted(startedAt: started, now: .now)
        if paywall.canStartTrip(tripsThisMonth: used, isUnlimited: purchases.isUnlimited) {
            isStarting = true
        } else {
            paywallReason = PaywallReasonItem(reason: .tripQuota(used: used))
        }
    }
}

/// The empty Trip tab: one job, starting a trip. The mascot welcomes; the last trip, when there is
/// one, reminds where and how much. Start sits in the bottom inset, out of this view.
private struct ReadyToShop: View {
    let lastTrip: ShoppingSession?

    var body: some View {
        // Centred when it fits, scrollable at the largest text sizes.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    MascotView(height: 220)
                    VStack(spacing: 8) {
                        Text("Ready to shop?")
                            .font(.title2.bold())
                        Text("Scan as you go and see your total before the till.")
                            .foregroundStyle(.secondary)
                    }
                    if let lastTrip {
                        Text("Last trip: \(lastTrip.store?.name ?? "Trip") · \(lastTrip.total.formatted()) · \(lastTrip.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.secondarySystemBackground), in: .capsule)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct PaywallReasonItem: Identifiable {
    let id = UUID()
    let reason: PaywallSheet.Reason
}

struct FinishedTrip: Identifiable {
    let session: ShoppingSession
    var id: UUID { session.id }
}
