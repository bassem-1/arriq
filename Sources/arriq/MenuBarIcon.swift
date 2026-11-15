import AppKit

/// The doorway, 18x18 template image so macOS tints it: an open-floored casing, the door swung in (outline),
/// and the lit room through the gap as the one solid shape. Matches the app icon.
/// Drawn as one transparency layer, so master off is a clean 0.32 with no doubled overlaps.
enum MenuBarIcon {
    static func image(enabled: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.setAlpha(enabled ? 1 : 0.32)
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            NSColor.black.set()

            let casing = NSBezierPath()
            casing.move(to: NSPoint(x: 3.8, y: 1.5))
            casing.line(to: NSPoint(x: 3.8, y: 16.2))
            casing.line(to: NSPoint(x: 14.2, y: 16.2))
            casing.line(to: NSPoint(x: 14.2, y: 1.5))
            casing.lineWidth = 1.5
            casing.stroke()

            let door = NSBezierPath()
            door.move(to: NSPoint(x: 3.8, y: 1.5))
            door.line(to: NSPoint(x: 9.2, y: 3.0))
            door.line(to: NSPoint(x: 9.2, y: 14.4))
            door.line(to: NSPoint(x: 3.8, y: 16.2))
            door.lineWidth = 1.2
            door.lineJoinStyle = .round
            door.stroke()

            let gap = NSBezierPath()
            gap.move(to: NSPoint(x: 9.2, y: 3.0))
            gap.line(to: NSPoint(x: 14.2, y: 1.5))
            gap.line(to: NSPoint(x: 14.2, y: 16.2))
            gap.line(to: NSPoint(x: 9.2, y: 14.4))
            gap.close()
            gap.fill()

            c.endTransparencyLayer()
            return true
        }
        img.isTemplate = true
        return img
    }
}
