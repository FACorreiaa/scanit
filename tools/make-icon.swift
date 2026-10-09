// Renders the ScanIt app icon (draft, owner approves). Original artwork: Apple's licence does not
// allow SF Symbols in app icons. Opaque 1024×1024 PNGs, because App Store Connect rejects alpha.
//
//   swift tools/make-icon.swift scanit/scanit/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO

struct Palette { let background: CGColor; let mark: CGColor }

let size = 1024
let variants: [(file: String, palette: Palette)] = [
    ("icon-light.png", Palette(background: CGColor(srgbRed: 0x23 / 255, green: 0x84 / 255, blue: 0x3B / 255, alpha: 1),
                               mark: CGColor(srgbRed: 0.99, green: 0.99, blue: 0.99, alpha: 1))),
    ("icon-dark.png", Palette(background: CGColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x13 / 255, alpha: 1),
                              mark: CGColor(srgbRed: 0x3C / 255, green: 0xC5 / 255, blue: 0x65 / 255, alpha: 1))),
    // Tinted: iOS colours a grayscale icon itself.
    ("icon-tinted.png", Palette(background: CGColor(gray: 0, alpha: 1), mark: CGColor(gray: 1, alpha: 1))),
]

func draw(_ palette: Palette, in context: CGContext) {
    let s = CGFloat(size)
    context.setFillColor(palette.background)
    context.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // Viewfinder corners.
    context.setStrokeColor(palette.mark)
    context.setLineWidth(44)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let inset: CGFloat = 212, arm: CGFloat = 150
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: inset, y: inset), 1, 1), (CGPoint(x: s - inset, y: inset), -1, 1),
        (CGPoint(x: inset, y: s - inset), 1, -1), (CGPoint(x: s - inset, y: s - inset), -1, -1),
    ]
    for (corner, dx, dy) in corners {
        context.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        context.addLine(to: corner)
        context.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
    }
    context.strokePath()

    // Barcode: bar widths in units, centred inside the viewfinder.
    let units: [CGFloat] = [3, 1, 2, 1, 4, 1, 1, 2, 3, 1, 2]
    let unit: CGFloat = 13, gap: CGFloat = 18
    let total = units.reduce(0) { $0 + $1 * unit } + gap * CGFloat(units.count - 1)
    var x = (s - total) / 2
    let barTop: CGFloat = s / 2 + 150, barBottom: CGFloat = s / 2 - 150
    context.setFillColor(palette.mark)
    for width in units {
        let rect = CGRect(x: x, y: barBottom, width: width * unit, height: barTop - barBottom)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: min(10, width * unit / 2), cornerHeight: 10, transform: nil))
        x += width * unit + gap
    }
    context.fillPath()
}

let directory = URL(filePath: CommandLine.arguments.dropFirst().first ?? ".")
for (file, palette) in variants {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    draw(palette, in: context)
    let url = directory.appending(path: file)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "could not write \(file)")
    print("wrote \(url.path)")
}
