// Cuts the mascot out of the brand sheet with Vision's subject lifting (the same model as
// "Lift subject from background" in Photos) and writes a transparent, trimmed PNG.
//
//   swiftc -O brand/tools/lift-mascot.swift -o /tmp/lift-mascot -framework Vision -framework CoreImage
//   /tmp/lift-mascot brand/source/brand-sheet.png brand/png/mascot.png
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

let args = CommandLine.arguments
let source = CGImageSourceCreateWithURL(URL(filePath: args[1]) as CFURL, nil)!
let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil)!

// The mascot with its scanned package: right of the logo, above the floor.
let illustration = sheet.cropping(to: CGRect(x: 680, y: 170, width: 800, height: 680))!

let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: illustration)
try handler.perform([request])
guard let result = request.results?.first else { fatalError("no subject found") }

let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
let image = CIImage(cvPixelBuffer: buffer)
let output = CIContext().createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
let destination = CGImageDestinationCreateWithURL(URL(filePath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, output, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(args[2])") }
print("mascot \(output.width)×\(output.height)")
