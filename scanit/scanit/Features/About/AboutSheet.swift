import SwiftData
import SwiftUI

/// The community link and the app version, opened from the info button on Insights. Moves into
/// Settings once that screen exists (`DESIGN.md` §8).
struct AboutSheet: View {
    @Environment(\.analytics) private var analytics
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var export: TripExportFile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        analytics.track(.discordLinkClicked(surface: .settings))
                        openURL(AppLinks.discord)
                    } label: {
                        Label("Join us on Discord", systemImage: "bubble.left.and.bubble.right")
                    }
                    .accessibilityIdentifier("aboutDiscord")
                }

                if let export {
                    Section {
                        ShareLink(item: export, preview: SharePreview("ScanItNow trips.csv")) {
                            Label("Export trips as CSV", systemImage: "tablecells")
                        }
                        .accessibilityIdentifier("exportTrips")
                    } footer: {
                        Text("Every finished trip, one row per item. The file goes only where you send it.")
                    }
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                        .monospacedDigit()
                }
            }
            .navigationTitle("About")
            .onAppear {
                let rows = TripExport.rows(context: context)
                export = rows.isEmpty ? nil : TripExportFile(csv: TripExport.csv(rows))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    /// Marketing version and build number, e.g. "1.0 (12)".
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        guard let build = info?["CFBundleVersion"] as? String else { return short }
        return "\(short) (\(build))"
    }
}

#Preview {
    AboutSheet()
}
