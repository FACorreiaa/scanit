// ScanItNow logo mark, redrawn as exact geometry from the brand sheet (brand/source/brand-sheet.png):
// four rounded green viewfinder brackets around a 2×2 grid of dark rounded squares, each with a
// square hole; the last square's hole is a notch in its top edge. Measurements: brand/tools/measure.swift.
//
// One model, three outputs, so web and iOS cannot drift apart:
//   brand/logo-mark.svg, brand/logo-mark-dark.svg   (web, docs)
//   AppIcon light / dark / tinted 1024 PNGs          (iOS)
//   brand/png/logo-mark-1024.png                     (anything raster)
//
//   swift brand/tools/make-mark.swift <repo root>
import CoreGraphics
import Foundation
import ImageIO

// MARK: - Model (240-unit design grid, measured from the sheet)

struct Palette {
    var background: (Double, Double, Double)?
    var green: (Double, Double, Double)
    var squares: (Double, Double, Double)
}

func hex(_ v: Int) -> (Double, Double, Double) {
    (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
}

let brandGreen = hex(0x10AA51)
let ink = hex(0x222A35)          // flattened from the sheet's #383F4C → #19242F gradient
let inkOnDark = hex(0xEEF1F5)
let paper = hex(0xFFFFFF)
let night = hex(0x10141A)

let grid: Double = 240
let stroke: Double = 22          // bracket thickness
let arm: Double = 96             // bracket outer length
let bend: Double = 30            // centre-line corner radius of a bracket
let square: Double = 52, gap: Double = 14, squareRadius: Double = 9
let hole: Double = 18, holeRadius: Double = 3

/// Centre-line polylines of the four brackets, as (start, corner, end) with the corner rounded.
func brackets() -> [(CGPoint, CGPoint, CGPoint)] {
    let o = stroke / 2, far = grid - stroke / 2, reach = arm - stroke / 2
    return [
        (CGPoint(x: o, y: reach), CGPoint(x: o, y: o), CGPoint(x: reach, y: o)),
        (CGPoint(x: grid - reach, y: o), CGPoint(x: far, y: o), CGPoint(x: far, y: reach)),
        (CGPoint(x: far, y: grid - reach), CGPoint(x: far, y: far), CGPoint(x: grid - reach, y: far)),
        (CGPoint(x: reach, y: far), CGPoint(x: o, y: far), CGPoint(x: o, y: grid - reach)),
    ]
}

/// Squares (outer rect) with their hole; the last square has a top notch instead (`notch` = true).
/// y grows downwards.
func squares() -> [(outer: CGRect, hole: CGRect, notch: Bool)] {
    let start = (grid - (2 * square + gap)) / 2
    var result: [(CGRect, CGRect, Bool)] = []
    for row in 0..<2 {
        for column in 0..<2 {
            let outer = CGRect(x: start + Double(column) * (square + gap), y: start + Double(row) * (square + gap),
                               width: square, height: square)
            let inset = (square - hole) / 2
            let notched = row == 1 && column == 1
            let h = notched
                ? CGRect(x: outer.minX + inset, y: outer.minY, width: hole, height: inset + hole * 0.55) // notch through the top edge
                : CGRect(x: outer.minX + inset, y: outer.minY + inset, width: hole, height: hole)
            result.append((outer, h, notched))
        }
    }
    return result
}

/// Points of the notched square's outline, clockwise from the top-left corner's end. Rounded
/// outer corners are handled by the callers through `squareRadius`.
func notchedOutline(_ o: CGRect, _ n: CGRect) -> CGPath {
    let p = CGMutablePath()
    let r = squareRadius, k = holeRadius
    p.move(to: CGPoint(x: o.minX + r, y: o.minY))
    p.addLine(to: CGPoint(x: n.minX, y: o.minY))
    p.addLine(to: CGPoint(x: n.minX, y: n.maxY - k))
    p.addArc(tangent1End: CGPoint(x: n.minX, y: n.maxY), tangent2End: CGPoint(x: n.maxX, y: n.maxY), radius: k)
    p.addArc(tangent1End: CGPoint(x: n.maxX, y: n.maxY), tangent2End: CGPoint(x: n.maxX, y: o.minY), radius: k)
    p.addLine(to: CGPoint(x: n.maxX, y: o.minY))
    p.addArc(tangent1End: CGPoint(x: o.maxX, y: o.minY), tangent2End: CGPoint(x: o.maxX, y: o.maxY), radius: r)
    p.addArc(tangent1End: CGPoint(x: o.maxX, y: o.maxY), tangent2End: CGPoint(x: o.minX, y: o.maxY), radius: r)
    p.addArc(tangent1End: CGPoint(x: o.minX, y: o.maxY), tangent2End: CGPoint(x: o.minX, y: o.minY), radius: r)
    p.addArc(tangent1End: CGPoint(x: o.minX, y: o.minY), tangent2End: CGPoint(x: o.minX + r, y: o.minY), radius: r)
    p.closeSubpath()
    return p
}

/// CGPath → SVG path data (lines, quad and cubic curves are all CGPath emits for arcs).
func svgPathData(_ path: CGPath) -> String {
    var d = ""
    path.applyWithBlock { element in
        let e = element.pointee, pts = e.points
        switch e.type {
        case .moveToPoint: d += "M\(f(pts[0].x)) \(f(pts[0].y))"
        case .addLineToPoint: d += "L\(f(pts[0].x)) \(f(pts[0].y))"
        case .addQuadCurveToPoint: d += "Q\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y))"
        case .addCurveToPoint: d += "C\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y)) \(f(pts[2].x)) \(f(pts[2].y))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

// MARK: - SVG

func f(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".00", with: "") }
func rgb(_ c: (Double, Double, Double)) -> String {
    String(format: "#%02X%02X%02X", Int((c.0 * 255).rounded()), Int((c.1 * 255).rounded()), Int((c.2 * 255).rounded()))
}

func roundedRectPath(_ r: CGRect, _ radius: Double) -> String {
    let x = r.minX, y = r.minY, w = r.width, h = r.height, k = min(radius, w / 2, h / 2)
    return "M\(f(x + k)) \(f(y))H\(f(x + w - k))A\(f(k)) \(f(k)) 0 0 1 \(f(x + w)) \(f(y + k))V\(f(y + h - k))"
        + "A\(f(k)) \(f(k)) 0 0 1 \(f(x + w - k)) \(f(y + h))H\(f(x + k))A\(f(k)) \(f(k)) 0 0 1 \(f(x)) \(f(y + h - k))"
        + "V\(f(y + k))A\(f(k)) \(f(k)) 0 0 1 \(f(x + k)) \(f(y))Z"
}

func svg(_ palette: Palette, squaresColor: String? = nil) -> String {
    var bracketPaths = ""
    for (a, c, b) in brackets() {
        // Round the corner with an arc of radius `bend` along the centre line.
        let dirA = CGPoint(x: (a.x - c.x).sign == .minus ? -1 : (a.x == c.x ? 0 : 1), y: (a.y - c.y).sign == .minus ? -1 : (a.y == c.y ? 0 : 1))
        let dirB = CGPoint(x: (b.x - c.x).sign == .minus ? -1 : (b.x == c.x ? 0 : 1), y: (b.y - c.y).sign == .minus ? -1 : (b.y == c.y ? 0 : 1))
        let p1 = CGPoint(x: c.x + dirA.x * bend, y: c.y + dirA.y * bend)
        let p2 = CGPoint(x: c.x + dirB.x * bend, y: c.y + dirB.y * bend)
        bracketPaths += "M\(f(a.x)) \(f(a.y))L\(f(p1.x)) \(f(p1.y))Q\(f(c.x)) \(f(c.y)) \(f(p2.x)) \(f(p2.y))L\(f(b.x)) \(f(b.y))"
    }
    var squarePaths = ""
    for (outer, h, notched) in squares() {
        squarePaths += notched ? svgPathData(notchedOutline(outer, h))
                               : roundedRectPath(outer, squareRadius) + roundedRectPath(h, holeRadius)
    }
    let background = palette.background.map { "<rect width=\"240\" height=\"240\" fill=\"\(rgb($0))\"/>" } ?? ""
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" role="img" aria-label="ScanItNow">
    \(background)<path d="\(bracketPaths)" fill="none" stroke="\(rgb(palette.green))" stroke-width="\(f(stroke))" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="\(squarePaths)" fill="\(squaresColor ?? rgb(palette.squares))" fill-rule="evenodd"/>
    </svg>

    """
}

// MARK: - Raster (CoreGraphics, same model)

func render(_ palette: Palette, size: Int, markScale: Double, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    let s = Double(size)
    if let bg = palette.background {
        ctx.setFillColor(CGColor(srgbRed: bg.0, green: bg.1, blue: bg.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
    }
    // Flip to SVG-like coordinates and scale the 240 grid into the canvas, centred.
    let scale = s * markScale / grid
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)
    ctx.translateBy(x: (s - grid * scale) / 2, y: (s - grid * scale) / 2)
    ctx.scaleBy(x: scale, y: scale)

    ctx.setStrokeColor(CGColor(srgbRed: palette.green.0, green: palette.green.1, blue: palette.green.2, alpha: 1))
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (a, c, b) in brackets() {
        ctx.move(to: a)
        ctx.addArc(tangent1End: c, tangent2End: b, radius: bend)
        ctx.addLine(to: b)
    }
    ctx.strokePath()

    let path = CGMutablePath()
    for (outer, h, notched) in squares() {
        if notched {
            path.addPath(notchedOutline(outer, h))
        } else {
            path.addRoundedRect(in: outer, cornerWidth: squareRadius, cornerHeight: squareRadius)
            path.addRoundedRect(in: h, cornerWidth: holeRadius, cornerHeight: holeRadius)
        }
    }
    ctx.setFillColor(CGColor(srgbRed: palette.squares.0, green: palette.squares.1, blue: palette.squares.2, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath(using: .evenOdd)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, nil)
    precondition(CGImageDestinationFinalize(d))
    print("wrote \(url.path)")
}

// MARK: - Outputs

let root = URL(filePath: CommandLine.arguments.dropFirst().first ?? ".")
let brand = root.appending(path: "brand")
let light = Palette(background: nil, green: brandGreen, squares: ink)
let dark = Palette(background: nil, green: brandGreen, squares: inkOnDark)

try svg(light).write(to: brand.appending(path: "logo-mark.svg"), atomically: true, encoding: .utf8)
try svg(dark).write(to: brand.appending(path: "logo-mark-dark.svg"), atomically: true, encoding: .utf8)
// Squares follow the text colour: dark ink on light pages, light ink on dark ones.
try svg(light, squaresColor: "currentColor").write(to: brand.appending(path: "logo-mark-currentcolor.svg"), atomically: true, encoding: .utf8)
print("wrote SVGs")
writePNG(render(light, size: 1024, markScale: 1, opaque: false), brand.appending(path: "png/logo-mark-1024.png"))

// App icon: the mark at 70% of the canvas leaves the margin iOS's squircle mask needs.
let icons = root.appending(path: "scanit/scanit/Assets.xcassets/AppIcon.appiconset")
writePNG(render(Palette(background: paper, green: brandGreen, squares: ink), size: 1024, markScale: 0.70, opaque: true),
         icons.appending(path: "icon-light.png"))
writePNG(render(Palette(background: night, green: brandGreen, squares: inkOnDark), size: 1024, markScale: 0.70, opaque: true),
         icons.appending(path: "icon-dark.png"))
// Tinted: iOS recolours a grayscale icon; brackets stay brighter than the squares for contrast.
writePNG(render(Palette(background: (0, 0, 0), green: (1, 1, 1), squares: (0.62, 0.62, 0.62)), size: 1024, markScale: 0.70, opaque: true),
         icons.appending(path: "icon-tinted.png"))

// Launch screen: the mark at 112 pt, transparent, @2x/@3x, light and dark (UILaunchScreen shows
// images at their natural size).
let launch = root.appending(path: "scanit/scanit/Assets.xcassets/LaunchMark.imageset")
for (suffix, palette) in [("", light), ("-dark", dark)] {
    for scale in [2, 3] {
        writePNG(render(palette, size: 112 * scale, markScale: 1, opaque: false),
                 launch.appending(path: "launch-mark\(suffix)@\(scale)x.png"))
    }
}
