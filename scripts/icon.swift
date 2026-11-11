import AppKit

let destination = CommandLine.arguments[1]
let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".iconset")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: folder) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let s = CGFloat(pixels)
        let frame = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
        let path = NSBezierPath(roundedRect: frame, xRadius: s * 0.21, yRadius: s * 0.21)
        NSColor.black.setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        path.lineWidth = max(1, s * 0.003)
        path.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: s * 0.365, y: s * 0.365, width: s * 0.27, height: s * 0.27)).fill()
        NSColor.white.setStroke()
        for ray in 0..<8 {
            let angle = CGFloat(ray) * .pi / 4
            let line = NSBezierPath()
            line.lineWidth = s * 0.031
            line.lineCapStyle = .round
            line.move(to: NSPoint(x: s * (0.5 + cos(angle) * 0.205), y: s * (0.5 + sin(angle) * 0.205)))
            line.line(to: NSPoint(x: s * (0.5 + cos(angle) * 0.278), y: s * (0.5 + sin(angle) * 0.278)))
            line.stroke()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", folder.path, "-o", destination]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
