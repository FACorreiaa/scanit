// ScanItNow logo mark, redrawn as exact geometry from the brand sheet (brand/source/brand-sheet.png):
// four rounded viewfinder brackets around a shopping cart. The sheet's glow is not part of the mark.
//
// One model, every output, so web and iOS cannot drift apart:
//   brand/logo-mark.svg, logo-mark-dark.svg, logo-mark-currentcolor.svg   (web, docs, in-app mark)
//   AppIcon light / dark / tinted 1024 PNGs                               (iOS)
//   LaunchMark @2x / @3x, light and dark                                  (iOS launch screen)
//   brand/png/logo-mark-1024.png                                          (anything raster)
//
//   swift brand/tools/make-mark.swift <repo root>
import CoreGraphics
import Foundation
import ImageIO

// MARK: - Palette

struct RGB {
    let r, g, b: Double
    init(_ v: Int) {
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }
    var hex: String { String(format: "#%02X%02X%02X", Int(r * 255 + 0.5), Int(g * 255 + 0.5), Int(b * 255 + 0.5)) }
    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

/// A bracket fades between two close colours, from the outside of its corner to the inside.
struct Fade {
    let from, to: RGB
}

struct Palette {
    var teal: Fade
    var lime: Fade
    var cart: RGB
    var background: RGB?
}

let onDark = Palette(teal: Fade(from: RGB(0x3FDCC6), to: RGB(0x6FEBD8)),
                     lime: Fade(from: RGB(0xBDF27A), to: RGB(0x86E23A)),
                     cart: RGB(0xF2F2EC))
// Deeper, because the sheet's teal and lime fall below 3:1 on white.
let onLight = Palette(teal: Fade(from: RGB(0x0FA892), to: RGB(0x27BFA8)),
                      lime: Fade(from: RGB(0x7CC62A), to: RGB(0x55A81A)),
                      cart: RGB(0x222A35))
// iOS recolours a grayscale icon, so brackets are flat and the cart stays brighter than the fade would.
let tinted = Palette(teal: Fade(from: RGB(0xFFFFFF), to: RGB(0xFFFFFF)),
                     lime: Fade(from: RGB(0xFFFFFF), to: RGB(0xFFFFFF)),
                     cart: RGB(0xB8B8B8))
let night = RGB(0x0B1014)
let black = RGB(0x000000)

// MARK: - Model (580 × 475 design units, measured from the sheet)

let width = 580.0, height = 475.0
let bracketStroke = 50.0, cartStroke = 35.0, wheelRadius = 25.0

enum Corner: String, CaseIterable {
    case topLeft = "tl", topRight = "tr", bottomLeft = "bl", bottomRight = "br"

    var svgPath: String {
        switch self {
        case .topLeft: "M25 145V95A70 70 0 0 1 95 25H155"
        case .topRight: "M425 25H485A70 70 0 0 1 555 95V145"
        case .bottomLeft: "M25 333V380A70 70 0 0 0 95 450H155"
        case .bottomRight: "M425 450H485A70 70 0 0 0 555 380V333"
        }
    }

    func path() -> CGPath {
        let p = CGMutablePath()
        switch self {
        case .topLeft:
            p.move(to: CGPoint(x: 25, y: 145)); p.addLine(to: CGPoint(x: 25, y: 95))
            p.addArc(tangent1End: CGPoint(x: 25, y: 25), tangent2End: CGPoint(x: 95, y: 25), radius: 70)
            p.addLine(to: CGPoint(x: 155, y: 25))
        case .topRight:
            p.move(to: CGPoint(x: 425, y: 25)); p.addLine(to: CGPoint(x: 485, y: 25))
            p.addArc(tangent1End: CGPoint(x: 555, y: 25), tangent2End: CGPoint(x: 555, y: 95), radius: 70)
            p.addLine(to: CGPoint(x: 555, y: 145))
        case .bottomLeft:
            p.move(to: CGPoint(x: 25, y: 333)); p.addLine(to: CGPoint(x: 25, y: 380))
            p.addArc(tangent1End: CGPoint(x: 25, y: 450), tangent2End: CGPoint(x: 95, y: 450), radius: 70)
            p.addLine(to: CGPoint(x: 155, y: 450))
        case .bottomRight:
            p.move(to: CGPoint(x: 425, y: 450)); p.addLine(to: CGPoint(x: 485, y: 450))
            p.addArc(tangent1End: CGPoint(x: 555, y: 450), tangent2End: CGPoint(x: 555, y: 380), radius: 70)
            p.addLine(to: CGPoint(x: 555, y: 333))
        }
        return p
    }

    func fade(in palette: Palette) -> Fade {
        switch self {
        case .topLeft, .bottomRight: palette.teal
        case .topRight: palette.lime
        case .bottomLeft: Fade(from: palette.lime.to, to: palette.lime.from)
        }
    }

    /// Unit-square gradient endpoints, the same as the SVG's objectBoundingBox coordinates.
    var axis: (start: CGPoint, end: CGPoint) {
        switch self {
        case .topLeft, .bottomRight: (CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 0))
        case .topRight, .bottomLeft: (CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1))
        }
    }
}

let cartSVG = "M128 139H166Q174 139 176 147L213 282Q218 301 237 301H352Q373 301 383 282L434 191H241"
let wheels = [CGPoint(x: 237, y: 364), CGPoint(x: 345, y: 364)]

func cartPath() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 128, y: 139)); p.addLine(to: CGPoint(x: 166, y: 139))
    p.addQuadCurve(to: CGPoint(x: 176, y: 147), control: CGPoint(x: 174, y: 139))
    p.addLine(to: CGPoint(x: 213, y: 282))
    p.addQuadCurve(to: CGPoint(x: 237, y: 301), control: CGPoint(x: 218, y: 301))
    p.addLine(to: CGPoint(x: 352, y: 301))
    p.addQuadCurve(to: CGPoint(x: 383, y: 282), control: CGPoint(x: 373, y: 301))
    p.addLine(to: CGPoint(x: 434, y: 191)); p.addLine(to: CGPoint(x: 241, y: 191))
    return p
}

// MARK: - SVG

func svg(_ palette: Palette, cartColor: String? = nil) -> String {
    let ink = cartColor ?? palette.cart.hex
    let defs = Corner.allCases.map { corner in
        let fade = corner.fade(in: palette), axis = corner.axis
        return """
        <linearGradient id="\(corner.rawValue)" x1="\(Int(axis.start.x))" y1="\(Int(axis.start.y))" x2="\(Int(axis.end.x))" y2="\(Int(axis.end.y))">\
        <stop offset="0" stop-color="\(fade.from.hex)"/><stop offset="1" stop-color="\(fade.to.hex)"/></linearGradient>
        """
    }.joined(separator: "\n")
    let brackets = Corner.allCases.map { "<path stroke=\"url(#\($0.rawValue))\" d=\"\($0.svgPath)\"/>" }.joined(separator: "\n")
    let dots = wheels.map { "<circle cx=\"\(Int($0.x))\" cy=\"\(Int($0.y))\" r=\"\(Int(wheelRadius))\" fill=\"\(ink)\"/>" }.joined()
    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(width)) \(Int(height))" role="img" aria-label="ScanItNow">
    <defs>
    \(defs)
    </defs>
    <g fill="none" stroke-width="\(Int(bracketStroke))" stroke-linecap="round">
    \(brackets)
    </g>
    <path fill="none" stroke="\(ink)" stroke-width="\(Int(cartStroke))" stroke-linecap="round" stroke-linejoin="round" d="\(cartSVG)"/>
    \(dots)
    </svg>

    """
}

// MARK: - Raster

/// `markScale` is the mark's width as a share of the canvas.
func render(_ palette: Palette, size: Int, markScale: Double, opaque: Bool) -> CGImage {
    let info = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue)!
    if let background = palette.background {
        ctx.setFillColor(background.cg)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }
    let scale = Double(size) * markScale / width
    // Flip to the design grid's top-left origin and centre the mark on the canvas.
    ctx.translateBy(x: (Double(size) - width * scale) / 2, y: (Double(size) + height * scale) / 2)
    ctx.scaleBy(x: scale, y: -scale)

    for corner in Corner.allCases {
        let path = corner.path()
        let box = path.boundingBoxOfPath
        let fade = corner.fade(in: palette), axis = corner.axis
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: [fade.from.cg, fade.to.cg] as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setLineWidth(bracketStroke)
        ctx.setLineCap(.round)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: box.minX + axis.start.x * box.width, y: box.minY + axis.start.y * box.height),
                               end: CGPoint(x: box.minX + axis.end.x * box.width, y: box.minY + axis.end.y * box.height),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    ctx.setStrokeColor(palette.cart.cg)
    ctx.setLineWidth(cartStroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(cartPath())
    ctx.strokePath()
    ctx.setFillColor(palette.cart.cg)
    for wheel in wheels {
        ctx.fillEllipse(in: CGRect(x: wheel.x - wheelRadius, y: wheel.y - wheelRadius, width: wheelRadius * 2, height: wheelRadius * 2))
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let d = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, nil)
    guard CGImageDestinationFinalize(d) else { fatalError("could not write \(url.path)") }
}

func withBackground(_ palette: Palette, _ background: RGB) -> Palette {
    var copy = palette
    copy.background = background
    return copy
}

// MARK: - Outputs

let root = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let brand = root.appending(path: "brand")

try svg(onLight).write(to: brand.appending(path: "logo-mark.svg"), atomically: true, encoding: .utf8)
try svg(onDark).write(to: brand.appending(path: "logo-mark-dark.svg"), atomically: true, encoding: .utf8)
// Brackets stay in the light palette; the cart follows the CSS text colour.
try svg(onLight, cartColor: "currentColor").write(to: brand.appending(path: "logo-mark-currentcolor.svg"), atomically: true, encoding: .utf8)

writePNG(render(onLight, size: 1024, markScale: 1, opaque: false), brand.appending(path: "png/logo-mark-1024.png"))

// App icon: the mark at 70% of the canvas leaves the margin iOS's squircle mask needs. The tile is
// dark in both appearances, because the mark's lime and teal are weak on white.
let icons = root.appending(path: "scanit/scanit/Assets.xcassets/AppIcon.appiconset")
writePNG(render(withBackground(onDark, night), size: 1024, markScale: 0.70, opaque: true), icons.appending(path: "icon-light.png"))
writePNG(render(withBackground(onDark, night), size: 1024, markScale: 0.70, opaque: true), icons.appending(path: "icon-dark.png"))
writePNG(render(withBackground(tinted, black), size: 1024, markScale: 0.70, opaque: true), icons.appending(path: "icon-tinted.png"))

let launch = root.appending(path: "scanit/scanit/Assets.xcassets/LaunchMark.imageset")
for (palette, suffix) in [(onLight, ""), (onDark, "-dark")] {
    for scale in [2, 3] {
        writePNG(render(palette, size: 112 * scale, markScale: 1, opaque: false),
                 launch.appending(path: "launch-mark\(suffix)@\(scale)x.png"))
    }
}
// Favicon: the app icon's dark tile, so the light marks read on any browser theme.
let inner = svg(onDark).replacingOccurrences(of: " role=\"img\" aria-label=\"ScanItNow\"", with: " x=\"110\" y=\"162\" width=\"580\" height=\"475\"")
let favicon = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 800" role="img" aria-label="ScanItNow">
<rect width="800" height="800" rx="180" fill="\(night.hex)"/>
\(inner)</svg>

"""
try favicon.write(to: root.appending(path: "scanit-web/static/favicon.svg"), atomically: true, encoding: .utf8)
print("mark, app icons, launch mark and favicon written")
