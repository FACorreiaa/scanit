import AppKit
import CoreText
import Foundation
import ScanItCore
import Vision

// Usage:
//   swift run label-bench <folder>              score photos against <folder>/expected.json
//   swift run label-bench <folder> --dump       also print every recognised line
//   swift run label-bench --make-samples <dir>  render synthetic labels (pipeline smoke test only)
//
// expected.json: { "photo.jpg": { "currency": "EUR", "totalMinor": 199 }, "no-price.jpg": { "currency": "EUR", "totalMinor": null } }
// Vision's accurate text recogniser is the engine behind DataScanner's `.text()`, so this approximates
// on-device behaviour; the final check is still a real phone in a real shop (BACKLOG IOS-006/007).

struct Expectation: Decodable {
    let currency: String
    let totalMinor: Int?
}

func recognise(_ image: CGImage) throws -> [ScanItCore.RecognizedText] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["pt-PT", "en-US", "es-ES", "fr-FR", "de-DE"]
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { observation in
        observation.topCandidates(1).first.map {
            ScanItCore.RecognizedText(text: $0.string, height: Double(observation.boundingBox.height))
        }
    }
}

func loadImage(_ url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

func money(_ minor: Int?, _ currency: String) -> String {
    guard let minor else { return "none" }
    return Money(amountMinor: minor, currency: currency).decimalValue.formatted(.number.precision(.fractionLength(2))) + " " + currency
}

// MARK: - Synthetic samples

func renderLabel(lines: [(String, CGFloat)], to url: URL) throws {
    let size = CGSize(width: 900, height: 500)
    let context = CGContext(
        data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0.93, blue: 0.2, alpha: 1)) // yellow shelf label
    context.fill(CGRect(origin: .zero, size: size))
    var y = size.height - 40
    for (text, pointSize) in lines {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, pointSize, nil)
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: CGColor(gray: 0, alpha: 1)])
        let line = CTLineCreateWithAttributedString(attributed)
        y -= pointSize
        context.textPosition = CGPoint(x: 40, y: y)
        CTLineDraw(line, context)
        y -= 24
    }
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

func makeSamples(in directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let samples: [(String, [(String, CGFloat)], Int?)] = [
        ("milk.png", [("LEITE MEIO GORDO 1L", 40), ("0,89 €", 150), ("0,89 €/L", 34)], 89),
        ("cheese.png", [("Queijo flamengo 200 g", 40), ("2,49", 150), ("12,45 €/kg", 34)], 249),
        ("promo.png", [("Iogurte natural 4x125 g", 40), ("2 x 0,99", 120), ("PVP 1,98 €", 34)], 198),
        ("unit-only.png", [("Bananas", 44), ("1,29 €/kg", 120)], nil),
    ]
    var expected: [String: [String: Any]] = [:]
    for (file, lines, total) in samples {
        try renderLabel(lines: lines, to: directory.appending(path: file))
        expected[file] = ["currency": "EUR", "totalMinor": total as Any? ?? NSNull()]
    }
    let data = try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: directory.appending(path: "expected.json"))
    print("Wrote \(samples.count) synthetic labels and expected.json to \(directory.path)")
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
if let index = arguments.firstIndex(of: "--make-samples"), arguments.indices.contains(index + 1) {
    try makeSamples(in: URL(filePath: arguments[index + 1]))
    exit(0)
}
guard let folderPath = arguments.first(where: { !$0.hasPrefix("--") }) else {
    print("usage: label-bench <folder> [--dump] | --make-samples <dir>")
    exit(2)
}
let dump = arguments.contains("--dump")
let folder = URL(filePath: folderPath)
let expectations = try JSONDecoder().decode(
    [String: Expectation].self, from: Data(contentsOf: folder.appending(path: "expected.json"))
)

var hits = 0
var scored = 0
for file in expectations.keys.sorted() {
    guard let expectation = expectations[file] else { continue }
    guard let image = loadImage(folder.appending(path: file)) else {
        print("✗ \(file): cannot read image")
        continue
    }
    let texts = try recognise(image)
    let result = PriceParser(currency: expectation.currency).parse(texts)
    let got = result.best?.total.amountMinor
    let ok = got == expectation.totalMinor
    scored += 1
    if ok { hits += 1 }
    let confidence = result.best.map { String(format: "%.2f", $0.confidence) } ?? "-"
    print("\(ok ? "✓" : "✗") \(file): expected \(money(expectation.totalMinor, expectation.currency)), got \(money(got, expectation.currency)) (confidence \(confidence))")
    if dump || !ok {
        for text in texts.sorted(by: { $0.height > $1.height }) {
            print("     \(String(format: "%.3f", text.height))  \(text.text)")
        }
    }
}
let rate = scored == 0 ? 0 : Double(hits) / Double(scored) * 100
print(String(format: "\nPrefilled correctly: %d of %d (%.0f%%). Target (IOS-007): 70%%.", hits, scored, rate))
