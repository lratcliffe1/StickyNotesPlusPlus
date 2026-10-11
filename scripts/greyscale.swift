// Usage: swift scripts/greyscale.swift <in.png> <out.png>
// Writes a greyscale copy (luminance only), approximating iOS's Greyscale colour filter.
import CoreImage
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: greyscale.swift <in.png> <out.png>\n".utf8))
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
guard let image = CIImage(contentsOf: inputURL) else {
    FileHandle.standardError.write(Data("cannot read \(inputURL.path)\n".utf8))
    exit(1)
}

let mono = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
let context = CIContext()
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { exit(1) }
do {
    try context.writePNGRepresentation(of: mono, to: outputURL, format: .RGBA8, colorSpace: colorSpace)
} catch {
    FileHandle.standardError.write(Data("cannot write \(outputURL.path): \(error)\n".utf8))
    exit(1)
}
