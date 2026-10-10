import SwiftUI

/// Brand pieces from `brand/` (see brand/README.md). The mark and wordmark are vector assets with
/// light and dark variants; the mascot is a 3D illustration with a transparent background.
extension Color {
    /// Brand green from the logo (#10AA51). Decorative only: for text and buttons use the accent
    /// (#23843B), which passes WCAG AA with white text.
    static let brandGreen = Color(red: 0x10 / 255, green: 0xAA / 255, blue: 0x51 / 255)
}

/// The mascot on a soft green disc. The disc keeps its dark body readable on dark backgrounds.
struct MascotView: View {
    var height: CGFloat = 180
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image("Mascot")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .background {
                Circle()
                    .fill(Color.brandGreen.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    .frame(width: height * 0.95, height: height * 0.95)
                    .offset(y: height * 0.04)
            }
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
