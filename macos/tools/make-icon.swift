// swift macos/tools/make-icon.swift macos/icon.tiff
// Template input-source icon: rounded badge with ស knocked out (macOS tints it for light/dark).
import Cocoa

func rep(_ px: Int) -> NSBitmapImageRep {
    let r = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    r.size = NSSize(width: 16, height: 16)  // 16pt; 32px rep is @2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: r)
    let box = NSRect(x: 0.5, y: 1.5, width: 15, height: 13)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
    NSGraphicsContext.current!.compositingOperation = .destinationOut
    let s = NSAttributedString(string: "ស", attributes: [
        .font: NSFont(name: "Khmer Sangam MN", size: 12) ?? .systemFont(ofSize: 12),
        .foregroundColor: NSColor.black,
    ])
    let sz = s.size()
    s.draw(at: NSPoint(x: box.midX - sz.width / 2, y: box.midY - sz.height / 2))
    NSGraphicsContext.restoreGraphicsState()
    return r
}

let tiff = NSBitmapImageRep.tiffRepresentationOfImageReps(in: [rep(16), rep(32)], using: .none, factor: 0)!
try! tiff.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
