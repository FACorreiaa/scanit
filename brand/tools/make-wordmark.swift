// "ScanItNow" in Avenir Next Bold, as outlines, so the SVGs need no font. "It" is one solid green:
// no gradient and no glow, and the sheet's "ScanIt" lettering is not traced.
//
//   swiftc -O brand/tools/make-wordmark.swift -o /tmp/make-wordmark && /tmp/make-wordmark <repo root>
import CoreGraphics
import CoreText
import Foundation

let text = "ScanItNow"
let accent = 4..<6 // "It"
let size: CGFloat = 200
let tracking: CGFloat = -2.5 // Avenir Next sits loose at display sizes

let font = CTFontCreateWithName("AvenirNext-Bold" as CFString, size, nil)
let attributed = NSAttributedString(string: text, attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTKernAttributeName as String): tracking,
])
let line = CTLineCreateWithAttributedString(attributed)
let run = (CTLineGetGlyphRuns(line) as! [CTRun])[0]
let count = CTRunGetGlyphCount(run)
var glyphs = [CGGlyph](repeating: 0, count: count)
var origins = [CGPoint](repeating: .zero, count: count)
CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
CTRunGetPositions(run, CFRange(location: 0, length: count), &origins)
precondition(count == text.count, "expected one glyph per letter")

func outline(_ range: Range<Int>) -> CGPath {
    let path = CGMutablePath()
    for index in range {
        guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
        // y flips: fonts grow upward, SVG grows downward.
        path.addPath(glyph, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: origins[index].x, ty: 0))
    }
    return path
}

let whole = outline(0..<count).boundingBoxOfPath

func svgPath(_ path: CGPath) -> String {
    var d = ""
    func point(_ p: CGPoint) -> String { String(format: "%.1f %.1f", p.x - whole.minX, p.y - whole.minY) }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint: d += "M" + point(e.points[0])
        case .addLineToPoint: d += "L" + point(e.points[0])
        case .addQuadCurveToPoint: d += "Q" + point(e.points[0]) + " " + point(e.points[1])
        case .addCurveToPoint: d += "C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2])
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

func svg(ink: String, it: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(String(format: "%.1f %.1f", whole.width, whole.height))" role="img" aria-label="ScanItNow">
    <path fill="\(ink)" d="\(svgPath(outline(0..<accent.lowerBound)))\(svgPath(outline(accent.upperBound..<count)))"/>
    <path fill="\(it)" d="\(svgPath(outline(accent)))"/>
    </svg>

    """
}

let brand = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".").appending(path: "brand")
try svg(ink: "#222A35", it: "#2E8F2A").write(to: brand.appending(path: "wordmark.svg"), atomically: true, encoding: .utf8)
try svg(ink: "#F2F2EC", it: "#8FE04A").write(to: brand.appending(path: "wordmark-dark.svg"), atomically: true, encoding: .utf8)
try svg(ink: "currentColor", it: "#2E8F2A").write(to: brand.appending(path: "wordmark-currentcolor.svg"), atomically: true, encoding: .utf8)
print("wordmark written", Int(whole.width), "x", Int(whole.height))
