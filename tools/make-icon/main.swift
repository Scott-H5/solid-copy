// tools/make-icon/main.swift
//
// Draws Solid Copy's app icon: a white radio-waves symbol on a dark slate
// tile with a soft gradient, at every size macOS asks for, into
// macOS/Assets.xcassets/AppIcon.appiconset. Run it with:
//   bash tools/make-icon.sh
// Rerun it after changing the drawing below; project.yml picks the result up.
//
// The symbol is Apple's own (SF Symbol "antenna.radiowaves.left.and.right"),
// so the icon needs no outside artwork and no licence check.

import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let sizes = [16, 32, 64, 128, 256, 512, 1024]

// One master image, then each size drawn from it.
func master(_ side: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: side, height: side)
    // Apple's rounded-square tile, inset a little so the shadow has room.
    let inset = side * 0.1
    let tile = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                            xRadius: side * 0.18, yRadius: side * 0.18)
    let gradient = NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.20, blue: 0.29, alpha: 1),
                              ending: NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.14, alpha: 1))!
    gradient.draw(in: tile, angle: -90)

    // The symbol, white, centred on the tile.
    let config = NSImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        let origin = NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)
        symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let full = master(1024)
for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(full)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: folder.appendingPathComponent("icon_\(size).png"))
}
print("Wrote \(sizes.count) icon sizes to \(folder.path)")
