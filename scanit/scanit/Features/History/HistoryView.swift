import SwiftUI

/// Past trips grouped by month (BACKLOG IOS-011).
struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("No trips yet", systemImage: "clock.arrow.circlepath")
            } description: {
                Text("Finished trips show up here, grouped by month.")
            }
            .navigationTitle("History")
        }
    }
}

#Preview {
    HistoryView()
}
