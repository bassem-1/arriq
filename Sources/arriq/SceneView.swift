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

                HStack(spacing: 28) {
                    ForEach(DeviceKind.allCases, id: \.self) { kind in
                        VStack(spacing: 6) {
                            square(model.status(kind))
                            Text(kind.uiTitle)
                                .font(Theme.font(11)).foregroundColor(Theme.fg2)
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

    /// Outline while waiting, filled in as each device works, fully filled when done.
    private func square(_ status: DeviceStatus) -> some View {
        let fill: Color
        switch status {
        case .done: fill = Theme.fg
        case .working: fill = Theme.fg2
        default: fill = Color.clear
        }
        return RoundedRectangle(cornerRadius: 4)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
            .frame(width: 28, height: 28)
            .animation(.easeOut(duration: 0.18), value: status)
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
