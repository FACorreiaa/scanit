// Measures colour components in a crop of the brand sheet (used to redraw the logo mark exactly).
//   swift measure.swift <png> <x> <y> <w> <h>
import CoreGraphics
import Foundation
import ImageIO

let a = CommandLine.arguments
let src = CGImageSourceCreateWithURL(URL(filePath: a[1]) as CFURL, nil)!
let full = CGImageSourceCreateImageAtIndex(src, 0, nil)!
let rect = CGRect(x: Int(a[2])!, y: Int(a[3])!, width: Int(a[4])!, height: Int(a[5])!)
let img = full.cropping(to: rect)!
let w = img.width, h = img.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

enum Kind: Int { case none, green, dark }
func kind(_ x: Int, _ y: Int) -> Kind {
    let i = (y * w + x) * 4
    let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
    if g > 120 && g - r > 60 && g - b > 40 { return .green }
    if r + g + b < 3 * 110 { return .dark }
    return .none
}
var label = [Int](repeating: 0, count: w * h)
var next = 1
var boxes: [(Kind, Int, Int, Int, Int, Int, Int, Int, Int)] = [] // kind,minx,miny,maxx,maxy,count,sumR,sumG,sumB
for y in 0..<h { for x in 0..<w {
    let k = kind(x, y); guard k != .none, label[y * w + x] == 0 else { continue }
    var stack = [(x, y)]; label[y * w + x] = next
    var minx = x, maxx = x, miny = y, maxy = y, count = 0, sr = 0, sg = 0, sb = 0
    while let (cx, cy) = stack.popLast() {
        count += 1; let i = (cy * w + cx) * 4; sr += Int(px[i]); sg += Int(px[i+1]); sb += Int(px[i+2])
        minx = min(minx, cx); maxx = max(maxx, cx); miny = min(miny, cy); maxy = max(maxy, cy)
        for (dx, dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
            let nx = cx + dx, ny = cy + dy
            guard nx >= 0, ny >= 0, nx < w, ny < h, label[ny * w + nx] == 0, kind(nx, ny) == k else { continue }
            label[ny * w + nx] = next; stack.append((nx, ny))
        }
    }
    next += 1
    if count > 30 { boxes.append((k, minx, miny, maxx, maxy, count, sr / count, sg / count, sb / count)) }
}}
for b in boxes.sorted(by: { ($0.0.rawValue, $0.2, $0.1) < ($1.0.rawValue, $1.2, $1.1) }) {
    let hex = String(format: "#%02X%02X%02X", b.6, b.7, b.8)
    print("\(b.0) x \(b.1)-\(b.3) y \(b.2)-\(b.4) (\(b.3 - b.1 + 1)x\(b.4 - b.2 + 1)) px=\(b.5) avg \(hex)")
}
