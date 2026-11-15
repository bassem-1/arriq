#if DEBUG
import AppKit

/// Debug builds only: `--debug-open-popover` clicks our own status item and, with ARRIQ_DEBUG_SNAPSHOT=<png>,
/// writes the popover as the window server composites it (own windows need no screen-recording permission).
@MainActor
enum DebugSnapshot {
    static func openPopoverIfAsked() {
        guard CommandLine.arguments.contains("--debug-open-popover") else { return }
        setvbuf(stdout, nil, _IONBF, 0)  // the run is killed afterwards; don't lose buffered lines
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            click()
            guard let out = ProcessInfo.processInfo.environment["ARRIQ_DEBUG_SNAPSHOT"] else { return }
            // first frame and settled frame, then the main window
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { snapshot(to: out + ".early.png") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                snapshot(to: out)
                if let main = NSApp.windows.first(where: { $0.isVisible && $0.className == "NSWindow" }) {
                    write(main, to: out + ".window.png")
                }
            }
        }
    }

    private static func click() {
        for window in NSApp.windows where window.className.contains("StatusBar") {
            if let button = findButton(window.contentView) { button.performClick(nil); return }
        }
    }

    private static func snapshot(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.className.contains("MenuBarExtra") }) else {
            print("snapshot: no popover among", NSApp.windows.map { $0.className })
            return
        }
        print("snapshot:", window.className, window.frame, "opaque", window.isOpaque, "bg", window.backgroundColor)
        write(window, to: path)
    }

    private static func write(_ window: NSWindow, to path: String) {
        guard let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber),
                                               [.boundsIgnoreFraming, .bestResolution]),
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private static func findButton(_ view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let b = view as? NSButton { return b }
        for sub in view.subviews { if let b = findButton(sub) { return b } }
        return nil
    }
}
#endif
