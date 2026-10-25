import AppKit

// Procedural waveform artwork; no external images or fonts are required.
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: pixels, height: pixels).fill(using: .copy)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 86, y: 86, width: 852, height: 852), xRadius: 190, yRadius: 190)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 32; shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState(); shadow.set(); NSColor.systemTeal.setFill(); base.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.80, blue: 0.76, alpha: 1), ending: NSColor(calibratedRed: 0.06, green: 0.54, blue: 0.68, alpha: 1))!.draw(in: base, angle: -70)
    NSColor.white.withAlphaComponent(0.22).setStroke(); base.lineWidth = 3; base.stroke()
    NSColor.white.setFill()
    let heights: [CGFloat] = [128,250,390,560,390,250,128]
    for (index,height) in heights.enumerated() {
        NSBezierPath(roundedRect: NSRect(x: 254 + CGFloat(index)*78, y: 512-height/2, width: 48, height: height), xRadius: 24, yRadius: 24).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Icon rendering failed") }
    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
}
