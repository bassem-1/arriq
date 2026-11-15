import Combine
import SwiftUI
import ArriqKit

/// Desktop gadget, 140x140: arriq, the state word, a pulse dot, one caption line.
struct GadgetView: View {
    @ObservedObject var model: AppModel

    private var state: String {
        guard model.settings.enabled else { return "off" }
        if model.snapshot.armedUntil != nil { return "armed" }
        return model.snapshot.phoneHome == true ? "home" : "away"
    }

    private var caption: String {
        let phone = model.snapshot.phoneHome.map { $0 ? "home" : "away" } ?? "unknown"
        return "phone \(phone) · laptop \(model.snapshot.macHome ? "home" : "away")"
    }

    var body: some View {
        GadgetFace(state: state, on: model.settings.enabled, caption: caption, pulses: model.pulses)
            .accessibilityAction { model.settings.enabled.toggle() }
    }
}

/// The 140x140 face shared by the app's gadget and the after-quit helper's gadget.
struct GadgetFace: View {
    let state: String
    let on: Bool
    let caption: String
    let pulses: PassthroughSubject<Void, Never>

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22).fill(Theme.bg)
            RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.line, lineWidth: 1)
            VStack(alignment: .leading, spacing: 0) {
                Text("arriq")
                    .font(Theme.font(11)).foregroundColor(Theme.fg2)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Text(state)
                        .font(Theme.font(22, .medium))
                        .foregroundColor(on ? Theme.fg : Theme.dim)
                    PulseDot(pulses: pulses)
                }
                Spacer(minLength: 0)
                Text(caption)
                    .font(Theme.font(11)).foregroundColor(Theme.fg2)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .frame(width: GadgetGeometry.size.width, height: GadgetGeometry.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("arriq")
        .accessibilityValue("\(state) · \(caption)")
        .accessibilityAddTraits(.isButton)
    }
}
