import SwiftUI

/// Spending numbers and charts (`DESIGN.md` → Insights catalogue, BACKLOG INS-103).
/// Charts appear after 3 finished trips; until then, this placeholder.
struct InsightsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Insights after 3 trips", systemImage: "chart.bar")
            } description: {
                Text("Once you've finished 3 trips you'll see what you spend, where, and which prices went up.")
            }
            .navigationTitle("Insights")
        }
    }
}

#Preview {
    InsightsView()
}
