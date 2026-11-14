// swift ios/tools/make-icon.swift ios/App/Assets.xcassets/AppIcon.appiconset/icon.png
// iOS app icon: the brand ស (docs/img/icon.png) on a full-bleed, opaque square; iOS rounds the corners.
import AppKit
import UniformTypeIdentifiers

let px = 1024
let ctx = CGContext(
    data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1a / 255, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: px, height: px))

let line = CTLineCreateWithAttributedString(NSAttributedString(string: "ស", attributes: [
    .font: NSFont(name: "Khmer Sangam MN", size: 620) ?? .systemFont(ofSize: 620),
    .foregroundColor: NSColor(srgbRed: 0xed / 255, green: 0xea / 255, blue: 0xe3 / 255, alpha: 1),
]))
let ink = CTLineGetImageBounds(line, ctx)  // the glyph's drawn box, not its line box
ctx.textPosition = CGPoint(x: (CGFloat(px) - ink.width) / 2 - ink.minX, y: (CGFloat(px) - ink.height) / 2 - ink.minY)
CTLineDraw(line, ctx)

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let out = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(out, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(out), "could not write \(url)")
