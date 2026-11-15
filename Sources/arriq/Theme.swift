import AppKit
import Combine
import SwiftUI

/// Two colors only: black and #FF6B00 at fixed opacities. Nothing else is allowed in the ui.
/// `fg` is the one accent token: swap it here (e.g. to red) and the whole ui follows.
enum Theme {
    static let accentNS = NSColor(srgbRed: 1, green: 107 / 255, blue: 0, alpha: 1)
    static let bg = Color.black
    static let fg = Color(nsColor: accentNS)
    static let fg2 = fg.opacity(0.55)   // secondary text
    static let dim = fg.opacity(0.32)   // disabled
    static let line = fg.opacity(0.16)  // hairlines, outlines
    static let wash = fg.opacity(0.08)  // hover, selected, pressed

    static let pad: CGFloat = 16
    static let row: CGFloat = 32
    static let gap: CGFloat = 16
    static let radius: CGFloat = 10
    static let controlRadius: CGFloat = 6

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// System focus rings use the accent color, so turn them off where we can.
    @ViewBuilder func arriqFocus() -> some View {
        if #available(macOS 14, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }

    /// Full-width row with a wash on hover or when selected. The padding is cancelled, so nothing moves.
    func washRow(selected: Bool = false) -> some View {
        modifier(WashRow(selected: selected))
    }
}

private struct WashRow: ViewModifier {
    let selected: Bool
    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius)
                .fill(selected || hover ? Theme.wash : Color.clear))
            .padding(.horizontal, -8)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

/// Plain text button with a hover/pressed wash. Hover only changes the background, never the layout.
struct TextButton: View {
    let title: String
    var size: CGFloat = 13
    var color: Color = Theme.fg
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.font(size))
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(hover ? Theme.wash : .clear))
                // fitts: the hit area is a full 32pt row, the visible wash stays 24
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .arriqFocus()
        .onHover { hover = $0 }
        .accessibilityLabel(title)
    }
}

/// Dot that flashes when arrival actions fire: opacity 1 -> 0.16 over 180ms.
struct PulseDot: View {
    let pulses: PassthroughSubject<Void, Never>
    var size: CGFloat = 6
    @State private var opacity = 0.16

    var body: some View {
        Circle()
            .fill(Theme.fg)
            .frame(width: size, height: size)
            .opacity(opacity)
            .onReceive(pulses) { _ in flash() }
            .accessibilityHidden(true)
    }

    private func flash() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { opacity = 1 }
        Task { @MainActor in
            withAnimation(.linear(duration: 0.18)) { opacity = 0.16 }
        }
    }
}
