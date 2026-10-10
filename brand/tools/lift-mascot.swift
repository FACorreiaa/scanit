// Cuts the mascot out of the brand sheet with Vision's subject lifting (the same model as
// "Lift subject from background" in Photos) and writes a transparent, trimmed PNG.
//
//   swift brand/tools/lift-mascot.swift brand/source/brand-sheet.png brand/png/mascot.png
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

let args = CommandLine.arguments
let source = CGImageSourceCreateWithURL(URL(filePath: args[1]) as CFURL, nil)!
let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)!

// The illustration only: above the logo lockup at the bottom of the sheet.
let illustration = sheet.cropping(to: CGRect(x: 200, y: 140, width: 870, height: 770))!

let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: illustration)
try handler.perform([request])
guard let result = request.results?.first else { fatalError("no subject found") }
print("instances: \(result.allInstances.count)")

// Every instance (mascot, phone, basket, and the little "ping" strokes), cropped to their extent.
let buffer = try result.generateMaskedImage(
    ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true
)
let image = CIImage(cvPixelBuffer: buffer)
let context = CIContext()
let output = URL(filePath: args[2])
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try context.writePNGRepresentation(of: image, to: output, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
print("wrote \(output.path) \(Int(image.extent.width))x\(Int(image.extent.height))")
