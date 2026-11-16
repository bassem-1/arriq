// usage: swift scripts/make-banner.swift <icon-1024.png> <out.png>
// renders the readme header at 2x (2560x720): black, the doorway icon on the left, the name and tagline in
// sf mono, lower-case, orange on the opacity ladder. same two colours as the app.
import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: swift scripts/make-banner.swift <icon-1024.png> <out.png>") }
guard let icon = NSImage(contentsOfFile: args[1]) else { fail("could not read \(args[1])") }

let w = 2560, h = 720
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fail("could not allocate bitmap") }

func orange(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 1, green: 107 / 255, blue: 0, alpha: a) }
func mono(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont { .monospacedSystemFont(ofSize: size, weight: weight) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
NSColor.black.setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: 40, yRadius: 40).fill()

// the icon, its own squircle and margin included, so it sits on the same black
icon.draw(in: NSRect(x: 120, y: 40, width: 640, height: 640))

func text(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint) {
    NSString(string: s).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
}
text("arriq", mono(176, .medium), orange(1), at: NSPoint(x: 840, y: 380))
text("the room wakes up when you do.", mono(56, .regular), orange(0.55), at: NSPoint(x: 848, y: 280))
text("lamp · speaker · tv · on when you get home", mono(40, .regular), orange(0.32), at: NSPoint(x: 848, y: 180))
// hairline, as in the app
orange(0.16).setFill()
NSRect(x: 848, y: 140, width: 1560, height: 2).fill()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode png") }
do { try png.write(to: URL(fileURLWithPath: args[2])) } catch { fail("could not write \(args[2])") }
