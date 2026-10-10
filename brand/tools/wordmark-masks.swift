// Splits the "ScanItNow" lockup into two 1-bit masks (dark letters, green "It") at 4× size for
// potrace. Used by brand/tools/trace-wordmark.sh.
//   swift wordmark-masks.swift <sheet.png> <out-dir>
import CoreGraphics
import CoreImage
import Foundation
import ImageIO

let a = CommandLine.arguments
let sheet = CIImage(contentsOf: URL(filePath: a[1]))!
let out = URL(filePath: a[2])
// Wordmark region of the 1254² sheet (CoreImage origin is bottom-left).
let crop = CGRect(x: 320, y: 1254 - 1090, width: 880, height: 160)
let scale: CGFloat = 4
let lanczos = CIFilter(name: "CILanczosScaleTransform", parameters: [
    kCIInputImageKey: sheet.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY)),
    kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1,
])!.outputImage!
let w = Int(crop.width * scale), h = Int(crop.height * scale)
var px = [UInt8](repeating: 0, count: w * h * 4)
CIContext().render(lanczos, toBitmap: &px, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)

func write(_ name: String, _ inside: (Int, Int, Int) -> Bool) throws {
    // P1 (ASCII PBM), rows top to bottom; render(toBitmap:) already writes the top row first.
    var text = "P1\n\(w) \(h)\n"
    for y in 0..<h {
        var line = ""
        line.reserveCapacity(w * 2)
        for x in 0..<w {
            let i = (y * w + x) * 4
            line += inside(Int(px[i]), Int(px[i + 1]), Int(px[i + 2])) ? "1" : "0"
        }
        text += line + "\n"
    }
    try text.write(to: out.appending(path: name), atomically: true, encoding: .ascii)
    print("wrote \(name) \(w)x\(h)")
}
try write("dark.pbm") { r, g, b in r + g + b < 3 * 128 && !(g - r > 50) }
try write("green.pbm") { r, g, b in g > 110 && g - r > 50 && g - b > 30 }
