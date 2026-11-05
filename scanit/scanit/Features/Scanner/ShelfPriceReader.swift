import Algorithms
import ScanItCore
import UIKit
import VisionKit

/// What one shelf-label still offered the confirm sheet (BACKLOG IOS-007).
nonisolated struct LabelPriceOffer: Equatable, Sendable {
    /// Filled in for the user. `nil` when the label is too ambiguous to guess.
    let prefill: Money?
    /// Other item prices on the label, offered as one-tap chips. Never per-kg prices or multi-buys,
    /// whose single-item price would be a guess.
    let candidates: [Money]

    var isEmpty: Bool { prefill == nil && candidates.isEmpty }

    /// What the sheet shows as chips: the alternatives, plus the prefill so it can be restored
    /// after a wrong tap.
    var chips: [Money] { candidates.isEmpty ? [] : (prefill.map { [$0] } ?? []) + candidates }

    init(_ result: PriceParseResult) {
        let prefill = result.prefill?.total
        self.prefill = prefill
        self.candidates = Array(
            result.candidates
                .filter { !$0.isUnitPrice && !$0.isMultiBuy && $0.total != prefill }
                .map(\.total)
                .uniqued()
                .prefix(3)
        )
    }
}

/// Takes the still from the scanner that is already on screen, so the camera never restarts.
@MainActor final class ScannerCamera {
    weak var controller: DataScannerViewController?

    func photo() async throws -> UIImage {
        guard let controller else { throw CancellationError() }
        return try await controller.capturePhoto()
    }
}

/// Reads the price from a still on the device. The photo is never saved or sent anywhere.
nonisolated enum ShelfPriceReader {
    /// Enough for Vision to read a shelf label, and far quicker than the full-size photo.
    private static let longestSide: CGFloat = 2400

    static func offer(from photo: UIImage, currency: String, barcodePayload: String?) async throws -> LabelPriceOffer {
        try await Task.detached(priority: .userInitiated) {
            guard let image = upright(photo) else { throw CancellationError() }
            let read = try LabelReader.read(image)
            let barcode = barcodePayload.flatMap(read.box(ofBarcode:))
            return LabelPriceOffer(PriceParser(currency: currency).parse(read.texts, barcode: barcode))
        }.value
    }

    /// UI tests: the simulator has no camera, so the "label" comes from `UITEST_SHELF_TEXT`, one
    /// recognised line per `|`, tallest first.
    static func offer(fromTestText text: String, currency: String) -> LabelPriceOffer {
        let lines = text.split(separator: "|").enumerated().map { index, line in
            RecognizedText(text: String(line), height: 0.2 / Double(index + 1))
        }
        return LabelPriceOffer(PriceParser(currency: currency).parse(lines))
    }

    /// Vision reads pixels and ignores `imageOrientation`, while camera photos usually arrive
    /// rotated, so the still is redrawn the right way up.
    static func upright(_ photo: UIImage) -> CGImage? {
        let longest = max(photo.size.width, photo.size.height)
        let scale = longest > longestSide ? longestSide / longest : 1
        let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}
