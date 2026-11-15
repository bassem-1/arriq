import SwiftUI
import ArriqKit

extension DeviceStatus {
    /// Lower-case words for the ui.
    var uiLabel: String {
        switch self {
        case .notSetUp(let why): return why
        case .ready: return "ready"
        case .working: return "working"
        case .done: return "done"
        case .failed(let why): return "failed · \(why)"
        }
    }
}

/// Three-cell device state, fixed width so rows never shift:
/// notSetUp = dash, ready = 1 cell, working = 2, done = 3, failed = outlined dash.
struct DeviceStatusBar: View {
    let status: DeviceStatus

    private var level: Int {
        switch status {
        case .ready: return 1
        case .working: return 2
        case .done: return 3
        case .notSetUp, .failed: return 0
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                cell(i)
            }
        }
        .frame(height: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("device state")
        .accessibilityValue(status.uiLabel)
    }

    @ViewBuilder private func cell(_ i: Int) -> some View {
        if level > 0 {
            RoundedRectangle(cornerRadius: 2)
                .fill(i < level ? Theme.fg : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(i < level ? Color.clear : Theme.line, lineWidth: 1))
                .frame(width: 10, height: 14)
        } else if i == 0 {
            dash.frame(width: 10, height: 14)
        } else {
            Color.clear.frame(width: 10, height: 14)
        }
    }

    @ViewBuilder private var dash: some View {
        if case .failed = status {
            RoundedRectangle(cornerRadius: 1).strokeBorder(Theme.fg2, lineWidth: 1).frame(width: 10, height: 4)
        } else {
            RoundedRectangle(cornerRadius: 1).fill(Theme.dim).frame(width: 10, height: 2)
        }
    }
}
