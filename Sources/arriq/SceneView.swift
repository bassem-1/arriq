import SwiftUI
import ArriqKit

/// Left side of the window: the home ring, phone and laptop dots, three device squares, one readout line.
struct SceneView: View {
    @ObservedObject var model: AppModel

    private let frameSize = CGSize(width: 300, height: 232)
    private let center = CGPoint(x: 150, y: 116)
    private let ringRadius: CGFloat = 90
    // fixed slots so the dots never swap sides
    private let phoneAngle = 200.0
    private let laptopAngle = 330.0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let snap = model.snapshot
            let phonePoint = point(angle: phoneAngle, radius: radius(home: snap.phoneHome))
            let laptopPoint = point(angle: laptopAngle, radius: radius(home: snap.macHome))
            let armed = snap.armedUntil.map { $0 > now } ?? false

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(width: ringRadius * 2, height: ringRadius * 2)
                        .position(center)
                    Chord(from: phonePoint, to: laptopPoint, control: center)
                        .stroke(Theme.fg2, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .opacity(armed ? 1 : 0)
                    dot(phonePoint, opacity: snap.phoneHome == nil ? 0.16 : 1)
                    dot(laptopPoint, opacity: 1)
                }
                .frame(width: frameSize.width, height: frameSize.height)
                .animation(.easeOut(duration: 0.18), value: snap.phoneHome)
                .animation(.easeOut(duration: 0.18), value: snap.macHome)

                HStack(spacing: 12) {
                    ForEach(DeviceKind.allCases, id: \.self) { kind in
                        PowerSquare(title: kind.uiTitle, power: model.power(kind), status: model.status(kind)) {
                            model.toggle(kind)
                        }
                    }
                }

                Text(readout(snap, now: now))
                    .font(Theme.font(11)).foregroundColor(Theme.fg2)
                    .lineLimit(1)
                    .frame(height: 16)
            }
        }
    }

    private func dot(_ p: CGPoint, opacity: Double) -> some View {
        Circle()
            .fill(Theme.fg)
            .frame(width: 8, height: 8)
            .opacity(opacity)
            .position(p)
    }

    /// Home = inside the ring, away = outside, unknown = on the ring.
    private func radius(home: Bool?) -> CGFloat {
        switch home {
        case .some(true): return 60
        case .some(false): return 118
        case .none: return ringRadius
        }
    }


    private func point(angle: Double, radius: CGFloat) -> CGPoint {
        let a = angle * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(a)), y: center.y - radius * CGFloat(sin(a)))
    }

    private func readout(_ snap: EngineSnapshot, now: Date) -> String {
        if let armed = snap.armedUntil, armed > now {
            return "armed · \(Fmt.countdown(armed.timeIntervalSince(now))) left"
        }
        if let fired = snap.lastTrigger, now.timeIntervalSince(fired) < 3600 {
            return "fired \(Fmt.clock(fired))"
        }
        let phone = snap.phoneHome.map { $0 ? "home" : "away" } ?? "unknown"
        return "phone \(phone) · laptop \(snap.macHome ? "home" : "away")"
    }
}

/// Quadratic curve used as the dashed link between phone and laptop while armed.
private struct Chord: Shape {
    let from: CGPoint
    let to: CGPoint
    let control: CGPoint

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        p.addQuadCurve(to: to, control: control)
        return p
    }
}

/// One device as a power switch: filled = on, outline = off or unknown. Click toggles.
/// Poses: rest, hover, pressed, working, on, failed. Motion only moves between these.
private struct PowerSquare: View {
    let title: String
    let power: Bool?
    let status: DeviceStatus
    let action: () -> Void

    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var failed: Bool { if case .failed = status { return true } else { return false } }
    private var working: Bool { status == .working }

    private var fill: Color {
        if working { return Theme.fg2 }
        if power == true { return Theme.fg }
        return hover ? Theme.wash : .clear
    }

    private var word: String {
        if working { return "…" }
        if failed { return "failed" }
        switch power {
        case .some(true): return "on"
        case .some(false): return "off"
        case .none: return "–"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(failed ? Theme.fg2 : Theme.line,
                                      style: StrokeStyle(lineWidth: 1, dash: failed ? [3, 3] : [])))
                    .frame(width: 28, height: 28)
                Text(title).font(Theme.font(11)).foregroundColor(Theme.fg2)
                Text(word).font(Theme.font(11)).foregroundColor(Theme.dim)
            }
            // fitts: the whole column (square, name, state) is the target, 76 wide
            .frame(width: 76)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressPose(reduceMotion: reduceMotion))
        .arriqFocus()
        .onHover { hover = $0 }
        // motion: slow-out · base 180 · the fill answers a real change in the device, not the click
        .animation(reduceMotion ? .linear(duration: 0.18) : .easeOut(duration: 0.18), value: power)
        // motion: slow-out · quick 120 · working shows the moment the command leaves
        .animation(.easeOut(duration: 0.12), value: working)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(word)
        .accessibilityHint(power == true ? "turns \(title) off" : "turns \(title) on")
        .accessibilityAddTraits(.isButton)
    }
}

/// pressed pose: 0.96 scale, no wind-up (the press is the wind-up)
private struct PressPose: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            // motion: press · tap 80 · in on press, out on release
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
