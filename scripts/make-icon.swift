// usage: swift scripts/make-icon.swift <out.png>
// renders the 1024x1024 app icon: the doorway. a dark wall on the macOS grid (824pt tile, r185, centered,
// transparent margin), a door swung open into a lit room, warm light fanning across the floor toward you.
// orange is the only light; everything else is near-black, like gestyq's globe.
import AppKit

let canvas: CGFloat = 1024
let tile: CGFloat = 824
let t0 = (canvas - tile) / 2
let tileRect = CGRect(x: t0, y: t0, width: tile, height: tile)
let tileRadius: CGFloat = 185

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 2 else { fail("usage: swift scripts/make-icon.swift <out.png>") }
guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { fail("no srgb colour space") }

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let orange = rgb(255, 107, 0)
let ember = rgb(255, 150, 60)
let core = rgb(255, 196, 130)

func grad(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    guard let g = CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0)) else {
        fail("could not build gradient")
    }
    return g
}

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

func poly(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts)
    p.closeSubpath()
    return p
}

func fillLinear(_ c: CGContext, _ path: CGPath, _ g: CGGradient, _ a: CGPoint, _ b: CGPoint) {
    c.saveGState(); c.addPath(path); c.clip()
    c.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.restoreGState()
}

func fillRadial(_ c: CGContext, _ path: CGPath, _ g: CGGradient, _ center: CGPoint, _ r: CGFloat, sx: CGFloat = 1, sy: CGFloat = 1) {
    c.saveGState(); c.addPath(path); c.clip()
    c.translateBy(x: center.x, y: center.y); c.scaleBy(x: sx, y: sy)
    c.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: r, options: [])
    c.restoreGState()
}

/// bloom: the path in `color` under a same-colour shadow, a few passes wider each time
func glow(_ c: CGContext, _ path: CGPath, _ color: CGColor, blur: CGFloat, passes: Int, stroke width: CGFloat? = nil) {
    for i in 0..<passes {
        c.saveGState()
        c.setShadow(offset: .zero, blur: blur * CGFloat(i + 1), color: color)
        c.addPath(path)
        if let width {
            c.setStrokeColor(color); c.setLineWidth(width); c.setLineCap(.round); c.strokePath()
        } else {
            c.setFillColor(color); c.fillPath()
        }
        c.restoreGState()
    }
}

func stroke(_ c: CGContext, _ path: CGPath, _ color: CGColor, _ width: CGFloat) {
    c.saveGState(); c.addPath(path); c.setStrokeColor(color); c.setLineWidth(width)
    c.setLineCap(.round); c.setLineJoin(.round); c.strokePath(); c.restoreGState()
}

func drawDoorway(_ c: CGContext) {
    let sq = CGPath(roundedRect: tileRect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
    c.saveGState(); c.addPath(sq); c.setFillColor(rgb(0, 0, 0)); c.fillPath(); c.restoreGState()
    fillRadial(c, sq, grad([(0, rgb(22, 18, 16)), (1, rgb(0, 0, 0, 0))]), P(512, 760), 520, sx: 1.2, sy: 0.8)

    c.saveGState(); c.addPath(sq); c.clip()
    // wall and floor
    fillLinear(c, sq, grad([(0, rgb(16, 14, 13)), (1, rgb(5, 5, 5))]), P(0, t0 + tile), P(0, t0))
    let floorY: CGFloat = 250
    fillLinear(c, poly([P(t0, t0), P(t0 + tile, t0), P(t0 + tile, floorY), P(t0, floorY)]),
               grad([(0, rgb(3, 3, 3)), (1, rgb(9, 8, 8))]), P(0, t0), P(0, floorY))

    let fL: CGFloat = 382, fR: CGFloat = 642, fT: CGFloat = 760, edge: CGFloat = 548
    // light fan on the floor, from the gap toward the viewer
    let fan = poly([P(edge, floorY), P(fR, floorY), P(842, t0 - 40), P(470, t0 - 40)])
    fillLinear(c, fan, grad([(0, rgb(255, 130, 30, 0.62)), (0.6, rgb(255, 107, 0, 0.14)), (1, rgb(255, 107, 0, 0))]),
               P(0, floorY), P(0, t0 - 40))
    // the lit room through the gap: hot core, orange edges
    let gap = poly([P(edge, floorY + 18), P(fR, floorY), P(fR, fT), P(edge, fT - 34)])
    glow(c, gap, rgb(255, 107, 0, 0.95), blur: 60, passes: 3)
    fillLinear(c, gap, grad([(0, orange), (0.35, ember), (0.7, core), (1, ember)]), P(edge, 0), P(fR, 0))
    // casing: thin and dark, with a warm inner edge on the lit side
    let casing = CGMutablePath()
    casing.move(to: P(fL - 14, floorY)); casing.addLine(to: P(fL - 14, fT + 14))
    casing.addLine(to: P(fR + 14, fT + 14)); casing.addLine(to: P(fR + 14, floorY))
    stroke(c, casing, rgb(26, 24, 23), 22)
    stroke(c, poly([P(fR + 3, floorY), P(fR + 3, fT + 3)]), rgb(255, 140, 50, 0.7), 3)
    // the door, swung in: hinge left, free edge rim lit by the room
    let door = poly([P(fL, floorY), P(edge, floorY + 18), P(edge, fT - 34), P(fL, fT)])
    fillLinear(c, door, grad([(0, rgb(30, 27, 25)), (1, rgb(12, 11, 11))]), P(fL, 0), P(edge, 0))
    for (y0, y1) in [(CGFloat(300), CGFloat(480)), (CGFloat(520), CGFloat(700))] {
        func at(_ k: CGFloat, _ y: CGFloat) -> CGPoint {
            let squeeze = (y - floorY) / (fT - floorY)
            return P(fL + (edge - fL) * k, y + k * (18 - 52 * squeeze))
        }
        stroke(c, poly([at(0.18, y0), at(0.82, y0), at(0.82, y1), at(0.18, y1)]), rgb(255, 255, 255, 0.05), 3)
    }
    let free = CGMutablePath()
    free.move(to: P(edge, floorY + 18)); free.addLine(to: P(edge, fT - 34))
    glow(c, free, rgb(255, 107, 0, 0.7), blur: 12, passes: 1, stroke: 3)
    stroke(c, free, rgb(255, 170, 90), 3)
    c.setFillColor(rgb(255, 150, 60, 0.9))
    c.fillEllipse(in: CGRect(x: 520, y: 492, width: 12, height: 12))  // handle catching the light
    c.restoreGState()

    // glass edge: a hairline that catches light at the top and fades out at the bottom
    c.saveGState(); c.addPath(sq); c.setLineWidth(4); c.replacePathWithStrokedPath(); c.clip()
    c.drawLinearGradient(grad([(0, rgb(255, 255, 255, 0.10)), (0.5, rgb(255, 255, 255, 0.02)), (1, rgb(255, 255, 255, 0))]),
                         start: P(0, t0 + tile), end: P(0, t0), options: [])
    c.restoreGState()
}

let pixels = Int(canvas)
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0) else { fail("could not allocate bitmap") }
rep.size = NSSize(width: canvas, height: canvas)

guard let context = NSGraphicsContext(bitmapImageRep: rep) else { fail("could not create graphics context") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.cgContext.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
drawDoorway(context.cgContext)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not encode png") }
do {
    try png.write(to: URL(fileURLWithPath: args[1]))
} catch {
    fail("could not write \(args[1]): \(error.localizedDescription)")
}
