import AppKit
import SwiftUI
import ArriqKit

/// Menu bar popover, 300 wide. Presence, the three devices, one fire button, footer.
struct PopoverView: View {
    @ObservedObject var model: AppModel

    private var enabled: Bool { model.settings.enabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer().frame(height: Theme.gap)
            presence
            divider
            VStack(alignment: .leading, spacing: 0) {
                ForEach(DeviceKind.allCases, id: \.self) { kind in
                    deviceRow(kind)
                }
            }
            .opacity(enabled ? 1 : 0.32)
            .disabled(!enabled)
            HStack {
                TextButton(title: "fire now") { model.fireNow() }
                    .padding(.leading, -6)
                    .opacity(enabled ? 1 : 0.32)
                    .disabled(!enabled)
                Spacer()
                // switching things off is never blocked by the master switch
                TextButton(title: "all off") { model.turnOffAll() }
            }
            .frame(height: Theme.row)
            divider
            footer
        }
        .padding(Theme.pad)
        .frame(width: 300)
        .background(Theme.bg.ignoresSafeArea())
        .background(DarkWindow())
        .tint(Theme.fg)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("arriq").font(Theme.font(13, .medium)).foregroundColor(Theme.fg)
                    PulseDot(pulses: model.pulses)
                }
                Text("the room wakes up when you do.")
                    .font(Theme.font(11)).foregroundColor(Theme.fg2)
            }
            Spacer(minLength: 8)
            ArriqSwitch(isOn: $model.settings.enabled, label: "arriq")
        }
    }

    private var presence: some View {
        VStack(alignment: .leading, spacing: 0) {
            presenceRow("phone", phoneWord)
            presenceRow("laptop", model.snapshot.macHome ? "home" : "away")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(caption(now: context.date))
                    .font(Theme.font(11)).foregroundColor(Theme.fg2)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
            }
        }
        .padding(.top, 4)
    }

    private var phoneWord: String {
        model.snapshot.phoneHome.map { $0 ? "home" : "away" } ?? "unknown"
    }

    private func caption(now: Date) -> String {
        if let armed = model.snapshot.armedUntil, armed > now {
            return "waiting for laptop · \(Fmt.countdown(armed.timeIntervalSince(now)))"
        }
        return " "
    }

    private func presenceRow(_ name: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(name).font(Theme.font(13)).foregroundColor(Theme.fg)
            Text(value).font(Theme.font(11)).foregroundColor(Theme.fg2)
            Spacer(minLength: 0)
        }
        .frame(height: Theme.row)
    }

    private func deviceRow(_ kind: DeviceKind) -> some View {
        HStack(spacing: 8) {
            Text(kind.uiTitle)
                .font(Theme.font(13)).foregroundColor(Theme.fg)
                .frame(width: 80, alignment: .leading)
            DeviceStatusBar(status: model.status(kind))
            Spacer(minLength: 0)
            // hick: per-device test lives in the window (customize…); the popover keeps five choices
        }
        .frame(height: Theme.row)
    }

    private var footer: some View {
        HStack {
            TextButton(title: "customize…") { model.openWindow() }.padding(.leading, -6)
            Spacer()
            TextButton(title: "quit") { model.quit() }
            Text(model.version)
                .font(Theme.font(11)).foregroundColor(Theme.dim)
                .padding(.leading, 8)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 8)
    }
}

/// Forces the popover window dark and solid black, edge to edge: system chrome never renders light and
/// the translucent material behind the content is removed. Applied synchronously when the view lands in the
/// window (no grey first frame) and again every time the menu bar window is shown, because the system can put
/// its material back on reopen.
private struct DarkWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DarkWindowView() }
    func updateNSView(_ v: NSView, context: Context) { DarkWindowView.apply(v.window) }
}

private final class DarkWindowView: NSView {
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        Self.apply(window)
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification,
                                          NSWindow.didChangeOcclusionStateNotification,
                                          NSWindow.didResizeNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { note in
                MainActor.assumeIsolated { Self.apply(note.object as? NSWindow) }
            }
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    static func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        if let root = window.contentView?.superview ?? window.contentView { neutralise(root) }
    }

    private static func neutralise(_ view: NSView) {
        if let fx = view as? NSVisualEffectView {
            fx.state = .inactive
            fx.isHidden = true
        }
        for sub in view.subviews { neutralise(sub) }
    }
}
