import SwiftUI

/// One full-width prominent button pinned to the bottom of a screen (`DESIGN.md` → Design rule 2:
/// primary actions sit in the bottom third, in reach of the thumb holding the phone).
struct PrimaryActionBar: View {
    let title: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier(identifier)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
}

#Preview {
    Color.clear.safeAreaInset(edge: .bottom) {
        PrimaryActionBar(title: "Start shopping", identifier: "preview") {}
    }
}
