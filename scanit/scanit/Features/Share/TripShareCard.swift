import CoreTransferable
import ScanItCore
import SwiftUI
import UniformTypeIdentifiers

/// The picture shared from a finished trip (BACKLOG ADD-002). Drawn at a fixed size in the brand
/// green whatever the phone's appearance or text size, because it is an image, not a screen.
struct TripShareCard: View {
    let content: TripShareContent

    /// 4:5, the tallest shape chat and social apps show uncropped.
    static let size = CGSize(width: 360, height: 450)
    private static let green = Color(red: 0x23 / 255, green: 0x84 / 255, blue: 0x3B / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(content.storeName ?? "Grocery trip")
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(content.date, format: .dateTime.day().month(.wide).year())
                    .font(.system(size: 15))
                    .opacity(0.8)
            }

            Spacer(minLength: 16)

            Text(content.total.formatted())
                .font(.system(size: 68, weight: .light))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            if let progress = content.progress {
                bar(progress)
                    .padding(.top, 12)
            }
            if let result = content.result {
                Text(result)
                    .font(.system(size: 17, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 12)
            }
            Text(content.items)
                .font(.system(size: 15))
                .opacity(0.8)
                .padding(.top, 4)

            Spacer(minLength: 16)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ScanItNow")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Scan smart. Spend with clarity.")
                        .font(.system(size: 13))
                        .opacity(0.8)
                }
                Spacer()
                Image("Mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 96)
            }
        }
        .padding(28)
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(.white)
        .background(Self.green)
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    /// Drawn by hand: `ProgressView` does not survive `ImageRenderer`.
    private func bar(_ progress: Double) -> some View {
        Capsule()
            .fill(.white.opacity(0.25))
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(content.isOver ? Color(red: 1, green: 0.78, blue: 0.72) : .white)
                        .frame(width: max(8, proxy.size.width * progress))
                }
            }
    }

    /// The card as PNG data, 1080 × 1350 px.
    static func png(_ content: TripShareContent) -> Data? {
        let renderer = ImageRenderer(content: TripShareCard(content: content))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }
}

/// Handed to `ShareLink`. The image is drawn only when something asks for it.
nonisolated struct TripShareImage: Transferable, Sendable {
    let content: TripShareContent

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            guard let data = await TripShareCard.png(image.content) else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        .suggestedFileName("ScanItNow trip.png")
    }
}

/// "Share" for a finished trip, as a row or a toolbar button.
struct TripShareLink: View {
    let session: ShoppingSession

    var body: some View {
        let content = TripShareContent(session: session)
        ShareLink(
            item: TripShareImage(content: content),
            preview: SharePreview(content.caption, image: Image("LogoMark"))
        ) {
            Label("Share trip", systemImage: "square.and.arrow.up")
        }
        .accessibilityIdentifier("shareTrip")
    }
}

#Preview("Share card") {
    VStack(spacing: 16) {
        TripShareCard(content: TripShareContent(
            storeName: "Lidl", date: .now, total: Money(amountMinor: 4280, currency: "EUR"),
            limit: Money(amountMinor: 6000, currency: "EUR"), itemCount: 23
        ))
        TripShareCard(content: TripShareContent(
            storeName: nil, date: .now, total: Money(amountMinor: 6340, currency: "EUR"),
            limit: nil, itemCount: 1
        ))
    }
    .scaleEffect(0.7)
}
