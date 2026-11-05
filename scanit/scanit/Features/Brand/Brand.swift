import SwiftUI

/// Brand pieces from `brand/` (see brand/README.md). The mark and wordmark are vector assets with
/// light and dark variants; the mascot is a 3D illustration with a transparent background.
struct MascotView: View {
    var height: CGFloat = 180
    var body: some View {
        Image("Mascot")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

#Preview("Mascot") {
    HStack(spacing: 32) {
        MascotView()
        MascotView().environment(\.colorScheme, .dark).padding().background(.black)
    }
    .padding()
}
