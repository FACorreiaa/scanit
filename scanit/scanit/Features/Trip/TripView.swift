import ScanItCore
import SwiftData
import SwiftUI

/// Trip tab: the active trip, or an empty state with a big Start button. Owns the finish
/// summary because the active-trip screen disappears the moment the trip ends.
struct TripView: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(PurchaseStore.self) private var purchases
    @Environment(\.paywallPolicy) private var paywall
    @Environment(\.modelContext) private var context
    @State private var isStarting = false
    @State private var finished: FinishedTrip?
    @State private var paywallReason: PaywallReasonItem?
    @State private var startAfterPaywall = false

    var body: some View {
        NavigationStack {
            if let active = sessions.active {
                ActiveTripView(session: active) { finished = FinishedTrip(session: $0) }
            } else {
                ContentUnavailableView {
                    Label("No trip in progress", systemImage: "cart")
                } description: {
                    Text("Scan products as you shop and watch your total against your limit.")
                } actions: {
                    Button("Start shopping", action: requestStart)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("openStartTrip")
                }
                .navigationTitle("Trip")
            }
        }
        .sheet(isPresented: $isStarting) {
            StartTripSheet()
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $finished) { trip in
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

struct PaywallReasonItem: Identifiable {
    let id = UUID()
    let reason: PaywallSheet.Reason
}

struct FinishedTrip: Identifiable {
    let session: ShoppingSession
    var id: UUID { session.id }
}
