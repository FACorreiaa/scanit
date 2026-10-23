import SwiftUI

/// The community link and the app version, opened from the info button on Insights. Moves into
/// Settings once that screen exists (`DESIGN.md` §8).
struct AboutSheet: View {
    @Environment(\.analytics) private var analytics
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

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

                Section {
                    LabeledContent("Version", value: Self.version)
                        .monospacedDigit()
                }
            }
            .navigationTitle("About")
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
