// Draws the app icon: three glowing Morse signals (· — ·) on a dark rounded square.
// Usage: swift make-icon.swift output.png
import AppKit

let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824pt body inside a 1024 canvas
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.15, blue: 0.27, alpha: 1),
                    NSColor(srgbRed: 0.05, green: 0.06, blue: 0.11, alpha: 1)])!
    .draw(in: squircle, angle: -90)

let amber = NSColor(srgbRed: 1.0, green: 0.71, blue: 0.22, alpha: 1)
let glow = NSShadow()
glow.shadowColor = amber.withAlphaComponent(0.85)
glow.shadowBlurRadius = 60
glow.set()
amber.setFill()

let y: CGFloat = 512, h: CGFloat = 120
NSBezierPath(ovalIn: NSRect(x: 215, y: y - h / 2, width: h, height: h)).fill()                       // ·
NSBezierPath(roundedRect: NSRect(x: 375, y: y - h / 2, width: 274, height: h), xRadius: 60, yRadius: 60).fill() // —
NSBezierPath(ovalIn: NSRect(x: 689, y: y - h / 2, width: h, height: h)).fill()                       // ·

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
