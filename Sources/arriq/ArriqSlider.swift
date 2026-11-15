import SwiftUI

/// Custom slider: 2pt track at 16%, filled part at 100%, 10pt knob. Snaps to `step`.
struct ArriqSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let label: String
    var step: Double = 1
    private let knob: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let usable = max(1, geo.size.width - knob)
            let span = range.upperBound - range.lowerBound
            let t = CGFloat((value - range.lowerBound) / span)
            let x = min(max(t, 0), 1) * usable
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.line).frame(height: 2)
                Rectangle().fill(Theme.fg).frame(width: x + knob / 2, height: 2)
                Circle().fill(Theme.fg).frame(width: knob, height: knob).offset(x: x)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = Double(min(max((g.location.x - knob / 2) / usable, 0), 1))
                value = snapped(range.lowerBound + f * span)
            })
        }
        .frame(height: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func snapped(_ raw: Double) -> Double {
        let s = (raw / step).rounded() * step
        return min(max(s, range.lowerBound), range.upperBound)
    }
}
