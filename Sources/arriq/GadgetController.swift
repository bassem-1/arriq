import AppKit
import Combine
import SwiftUI
import ArriqKit

/// Borderless panel that tells a click from a drag itself (< 3pt of travel = click).
final class GadgetPanel: NSPanel {
    var onClick: (() -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var menuBuilder: (() -> NSMenu)?

    private var downMouse: NSPoint?
    private var downOrigin = NSPoint.zero
    private var moved = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            downMouse = NSEvent.mouseLocation
            downOrigin = frame.origin
            moved = false
        case .leftMouseDragged:
            guard let start = downMouse else { return }
            let m = NSEvent.mouseLocation
            let dx = m.x - start.x, dy = m.y - start.y
            if moved || hypot(dx, dy) >= 3 {
                moved = true
                setFrameOrigin(NSPoint(x: downOrigin.x + dx, y: downOrigin.y + dy))
            }
        case .leftMouseUp:
            guard downMouse != nil else { return }
            downMouse = nil
            if moved {
                onMoved?(frame.origin)
            } else if event.clickCount == 1 {
                // later clicks of a double-click are ignored, so one double tap toggles once
                onClick?()
            }
        case .rightMouseDown:
            if let menu = menuBuilder?(), let view = contentView {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
            }
        default:
            super.sendEvent(event)
        }
    }
}

/// Size, default spot and screen clamping, shared by the app's gadget and the after-quit helper.
@MainActor
enum GadgetGeometry {
    static let size = NSSize(width: 140, height: 140)

    static func origin(_ saved: [Double]?) -> CGPoint {
        guard let o = saved, o.count == 2 else { return clamp(defaultOrigin()) }
        return clamp(CGPoint(x: o[0], y: o[1]))
    }

    static func level(floats: Bool) -> NSWindow.Level {
        floats ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    static func makePanel() -> GadgetPanel {
        let p = GadgetPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false // dragging is handled in GadgetPanel
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        p.appearance = NSAppearance(named: .darkAqua)
        p.title = "arriq"
        return p
    }

    static func defaultOrigin() -> CGPoint {
        guard let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return .zero }
        return CGPoint(x: vf.maxX - size.width - 24, y: vf.maxY - size.height - 24)
    }

    /// Keep the whole gadget inside the screen it overlaps most.
    static func clamp(_ origin: CGPoint) -> CGPoint {
        let rect = CGRect(origin: origin, size: size)
        let best = NSScreen.screens.max { a, b in
            area(a.visibleFrame.intersection(rect)) < area(b.visibleFrame.intersection(rect))
        } ?? NSScreen.main
        guard let vf = best?.visibleFrame else { return origin }
        return CGPoint(x: min(max(origin.x, vf.minX), vf.maxX - size.width),
                       y: min(max(origin.y, vf.minY), vf.maxY - size.height))
    }

    private static func area(_ r: CGRect) -> CGFloat { r.isNull ? 0 : r.width * r.height }
}

/// Menu item with a closure, for the gadget's right-click menu.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func fire() { handler() }
}

@MainActor
final class GadgetController {
    private weak var model: AppModel?
    private var panel: GadgetPanel?
    private var bag = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        model.$settings
            .map { GadgetState(show: $0.gadgetEnabled, floats: $0.gadgetFloats) }
            .removeDuplicates()
            .sink { [weak self] state in self?.apply(state) }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reclamp() }
            .store(in: &bag)
    }

    private struct GadgetState: Equatable {
        var show: Bool
        var floats: Bool
    }

    private func apply(_ state: GadgetState) {
        guard state.show else { panel?.orderOut(nil); return }
        guard let panel = panel ?? makePanel() else { return }
        panel.level = GadgetGeometry.level(floats: state.floats)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> GadgetPanel? {
        guard let model else { return nil }
        let p = GadgetGeometry.makePanel()
        let host = NSHostingView(rootView: GadgetView(model: model))
        host.frame = NSRect(origin: .zero, size: GadgetGeometry.size)
        p.contentView = host
        p.onClick = { [weak self] in self?.model?.settings.enabled.toggle() }
        p.onMoved = { [weak self] origin in self?.moved(to: origin) }
        p.menuBuilder = { [weak self] in self?.buildMenu() ?? NSMenu() }
        p.setFrameOrigin(GadgetGeometry.origin(model.settings.gadgetOrigin))
        panel = p
        return p
    }

    private func moved(to origin: CGPoint) {
        let c = GadgetGeometry.clamp(origin)
        panel?.setFrameOrigin(c)
        model?.settings.gadgetOrigin = [Double(c.x), Double(c.y)]
    }

    private func reclamp() {
        guard let panel else { return }
        panel.setFrameOrigin(GadgetGeometry.clamp(panel.frame.origin))
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        let floats = model?.settings.gadgetFloats ?? false
        menu.addItem(ActionItem("customize…") { [weak self] in self?.model?.openWindow() })
        menu.addItem(ActionItem("turn everything off") { [weak self] in self?.model?.turnOffAll() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("hide gadget") { [weak self] in self?.model?.settings.gadgetEnabled = false })
        menu.addItem(ActionItem("float above windows", checked: floats) { [weak self] in
            self?.model?.settings.gadgetFloats.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(ActionItem("quit") { [weak self] in self?.model?.quit() })
        return menu
    }
}
