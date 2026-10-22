#if canImport(Vision)
import CoreGraphics
import Vision

/// What one still of a shelf label contains: every recognised line plus the barcodes, all in
/// the same `LabelBox` space.
public struct LabelRead: Sendable {
    public struct Barcode: Hashable, Sendable {
        public let payload: String
        public let box: LabelBox
    }

    public let texts: [RecognizedText]
    public let barcodes: [Barcode]

    public init(texts: [RecognizedText], barcodes: [Barcode]) {
        self.texts = texts
        self.barcodes = barcodes
    }

    /// The box of the barcode the scanner locked on, if Vision found it in this still too.
    public func box(ofBarcode payload: String) -> LabelBox? {
        barcodes.first { $0.payload == payload }?.box
    }
}

/// Reads a shelf-label still with Vision (BACKLOG IOS-006). The app and `tools/label-bench` call
/// this same code, so the bench measures what ships. Not available on Linux; the parser is.
public enum LabelReader {
    public static let defaultLanguages = ["pt-PT", "en-US", "es-ES", "fr-FR", "de-DE"]

    public static func read(_ image: CGImage, languages: [String] = defaultLanguages) throws -> LabelRead {
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = false
        text.recognitionLanguages = languages
        let barcodes = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage: image).perform([text, barcodes])

        let texts = (text.results ?? []).compactMap { observation -> RecognizedText? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedText(text: candidate.string, box: LabelBox(vision: observation.boundingBox))
        }
        let codes = (barcodes.results ?? []).compactMap { observation -> LabelRead.Barcode? in
            guard let payload = observation.payloadStringValue else { return nil }
            return LabelRead.Barcode(payload: payload, box: LabelBox(vision: observation.boundingBox))
        }
        return LabelRead(texts: texts, barcodes: codes)
    }
}

extension LabelBox {
    /// Vision boxes are normalised with the origin at the bottom left.
    init(vision rect: CGRect) {
        self.init(
            x: Double(rect.minX), y: Double(1 - rect.maxY),
            width: Double(rect.width), height: Double(rect.height)
        )
    }
}
#endif
