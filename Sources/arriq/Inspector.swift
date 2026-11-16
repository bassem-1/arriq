import AppKit
import SwiftUI
import ArriqKit

/// Text tabs over one pane. The tab row and the pane keep fixed positions, so nothing jumps.
struct Inspector: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            Rectangle().fill(Theme.line).frame(height: 1)
            pane
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(Array(InspectorTab.allCases.enumerated()), id: \.element.id) { index, tab in
                if index > 0 {
                    Text("·").font(Theme.font(11)).foregroundColor(Theme.dim)
                }
                TabLabel(title: tab.rawValue, selected: model.tab == tab) { model.tab = tab }
            }
        }
        .frame(height: Theme.row)
    }

    @ViewBuilder private var pane: some View {
        switch model.tab {
        case .devices: scrolled { DevicesTab(model: model) }
        case .phone: scrolled { PhoneTab(model: model) }
        case .home: scrolled { HomeTab(model: model) }
        case .log: LogTab(model: model)
        }
    }

    private func scrolled<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.top, 12)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TabLabel: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(title)
                    .font(Theme.font(11))
                    .foregroundColor(selected || hover ? Theme.fg : Theme.fg2)
                    .lineLimit(1)
                    .fixedSize()  // a tab name is never truncated
                    .frame(height: 24)
                Rectangle()
                    .fill(selected ? Theme.fg : Color.clear)
                    .frame(height: 1)
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .arriqFocus()
        .onHover { hover = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Label column (88pt) plus any control. Every row is 32pt tall.
struct SettingRow<Content: View>: View {
    let title: String
    let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(Theme.font(11)).foregroundColor(Theme.fg2)
                .frame(width: 88, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Theme.row)
    }
}

/// Slider plus a right-aligned readout, the common pairing in the inspector.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let readout: (Double) -> String

    var body: some View {
        SettingRow(title) {
            HStack(spacing: 8) {
                ArriqSlider(value: $value, range: range, label: title, step: step)
                Text(readout(value))
                    .font(Theme.font(11)).foregroundColor(Theme.fg2)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

private struct DevicesTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(DeviceKind.allCases, id: \.self) { kind in
                deviceRow(kind)
            }
            HStack(spacing: 0) {
                TextButton(title: "all on", size: 11) { model.turnOnAll() }.padding(.leading, -6)
                Spacer(minLength: 24)
                TextButton(title: "all off", size: 11) { model.turnOffAll() }.padding(.trailing, -6)
            }
            .frame(height: Theme.row)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 8)
            controls(for: model.device)
        }
    }

    private func deviceRow(_ kind: DeviceKind) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(kind.uiTitle)
                    .font(Theme.font(13))
                    .foregroundColor(Theme.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let why = failedReason(model.status(kind)) {
                    Text(why)
                        .font(Theme.font(11)).foregroundColor(Theme.fg2)
                        .lineLimit(1)
                }
                DeviceStatusBar(status: model.status(kind))
            }
            .frame(height: Theme.row)
            .washRow(selected: model.device == kind)
            .onTapGesture { model.device = kind }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(model.device == kind ? .isSelected : [])

            if kind == .lamp, model.settings.lampBrand == .govee, failedReason(model.status(kind)) != nil {
                lampHelp
            }
        }
    }

    private var lampHelp: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("the lamp must be on the same wifi as this mac.")
            Text("govee home › lamp › settings › lan control must be on.")
        }
        .font(Theme.font(11)).foregroundColor(Theme.fg2)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private func failedReason(_ status: DeviceStatus) -> String? {
        if case .failed(let why) = status { return why }
        return nil
    }

    private func controls(for kind: DeviceKind) -> some View {
        let setting = model.setting(kind)
        return VStack(alignment: .leading, spacing: 0) {
            SettingRow("status") {
                Text(model.status(kind).uiLabel)
                    .font(Theme.font(11)).foregroundColor(Theme.fg2)
                    .lineLimit(1)
            }
            // the two most used actions, near the top; opposite verbs at opposite ends so a miss never flips it
            HStack(spacing: 0) {
                TextButton(title: "turn on") { model.turnOn(kind) }.padding(.leading, -6)
                Spacer(minLength: 24)
                TextButton(title: "turn off") { model.turnOff(kind) }.padding(.trailing, -6)
            }
            .frame(height: Theme.row)
            // frequency of use: the lamp's live controls come before its arrival settings
            if kind == .lamp { kindControls(kind) }
            SettingRow("on arrival") {
                ArriqSwitch(isOn: enabledBinding(kind), label: "\(kind.uiTitle) on arrival")
            }
            SliderRow(title: "delay", value: delayBinding(kind), range: 0...120, step: 5) {
                "\(Int($0)) s"
            }
            .opacity(setting.enabled ? 1 : 0.32)
            .disabled(!setting.enabled)
            if kind != .lamp { kindControls(kind) }
        }
    }

    /// postel: dashes, no separators, any case are accepted; a complete address is stored in one canonical form
    private var speakerAddressBinding: Binding<String> {
        Binding(get: { model.settings.speakerAddress },
                set: { v in model.settings.speakerAddress = SpeakerWake.normalize(v) ?? v })
    }

    @ViewBuilder private func kindControls(_ kind: DeviceKind) -> some View {
        switch kind {
        case .lamp:
            SettingRow("brand") {
                HStack(spacing: 6) {
                    ForEach(Array(LampBrand.allCases.enumerated()), id: \.element) { index, brand in
                        if index > 0 { Text("·").font(Theme.font(11)).foregroundColor(Theme.dim) }
                        TabLabel(title: brand.rawValue, selected: model.settings.lampBrand == brand) {
                            model.settings.lampBrand = brand
                        }
                    }
                }
                .fixedSize()
            }
            if model.settings.lampBrand == .hue { HueControls(model: model) }
            SliderRow(title: "brightness", value: brightnessBinding, range: 1...100) {
                "\(Int($0))"
            }
            SettingRow("light") {
                HStack(spacing: 6) {
                    ForEach(Array(LampMode.allCases.enumerated()), id: \.element) { index, mode in
                        if index > 0 { Text("·").font(Theme.font(11)).foregroundColor(Theme.dim) }
                        TabLabel(title: mode.rawValue, selected: model.settings.lampMode == mode) {
                            model.settings.lampMode = mode
                        }
                    }
                }
                .fixedSize()
            }
            if model.settings.lampMode == .white {
                SliderRow(title: "warmth", value: kelvinBinding, range: 2000...9000, step: 100) {
                    "\(Int($0))k"
                }
            } else {
                // two-colour ui: the hue is named, never shown as a swatch
                SliderRow(title: "color", value: hueBinding, range: 0...359) {
                    LampColor.name(hue: Int($0))
                }
            }
            if model.power(.lamp) != true {
                Text("changes reach the lamp while it is on")
                    .font(Theme.font(11)).foregroundColor(Theme.dim)
                    .frame(height: 24, alignment: .leading)
            }
        case .speaker:
            SettingRow("address") {
                TextField("bluetooth address", text: speakerAddressBinding)
                    .arriqField()
            }
            if !model.settings.speakerAddress.isEmpty && SpeakerWake.addressBytes(model.settings.speakerAddress) == nil {
                HStack {
                    Text("not a bluetooth address").font(Theme.font(11)).foregroundColor(Theme.fg2)
                    Spacer()
                }
                .frame(height: Theme.row)
            }
            SettingRow("play music") {
                ArriqSwitch(isOn: $model.settings.musicEnabled, label: "play music")
            }
            SettingRow("spotify link") {
                TextField("paste spotify link", text: $model.settings.spotifyLink)
                    .arriqField()
            }
            if !model.settings.spotifyLink.isEmpty && SpotifyLink.uri(from: model.settings.spotifyLink) == nil {
                HStack {
                    Text("not a spotify link").font(Theme.font(11)).foregroundColor(Theme.fg2)
                    Spacer()
                }
                .frame(height: Theme.row)
            }
            SliderRow(title: "volume", value: musicVolumeBinding, range: 0...100, step: 5) {
                "\(Int($0))"
            }
            SettingRow("shuffle") {
                ArriqSwitch(isOn: $model.settings.musicShuffle, label: "shuffle")
            }
            HStack {
                TextButton(title: "test music") { model.testMusic() }.padding(.leading, -6)
                Spacer()
            }
            .frame(height: Theme.row)
        case .tv:
            TVControls(model: model)
        }
    }

    private func enabledBinding(_ kind: DeviceKind) -> Binding<Bool> {
        Binding(get: { model.setting(kind).enabled },
                set: { v in model.updateDevice(kind) { $0.enabled = v } })
    }

    private func delayBinding(_ kind: DeviceKind) -> Binding<Double> {
        Binding(get: { Double(model.setting(kind).delaySeconds) },
                set: { v in model.updateDevice(kind) { $0.delaySeconds = Int(v) } })
    }

    private var brightnessBinding: Binding<Double> {
        Binding(get: { Double(model.settings.lampBrightness) },
                set: { model.settings.lampBrightness = Int($0) })
    }

    private var musicVolumeBinding: Binding<Double> {
        Binding(get: { Double(model.settings.musicVolume) },
                set: { model.settings.musicVolume = Int($0) })
    }

    private var hueBinding: Binding<Double> {
        Binding(get: { Double(model.settings.lampHue) },
                set: { model.settings.lampHue = Int($0) })
    }

    private var kelvinBinding: Binding<Double> {
        Binding(get: { Double(model.settings.lampKelvin) },
                set: { model.settings.lampKelvin = Int($0) })
    }
}

extension View {
    /// the plain bordered text field look used across the inspector
    func arriqField() -> some View {
        self.textFieldStyle(.plain)
            .font(Theme.font(11))
            .foregroundColor(Theme.fg)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius)
                .strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Token field (secret goes straight to the engine and is cleared) and a list of the account's tvs.
private struct TVControls: View {
    @ObservedObject var model: AppModel
    @State private var token = ""
    @State private var saved = false
    @State private var devices: [SmartThingsDevice] = []
    @State private var loading = false

    private var note: String {
        saved || model.snapshot.smartThingsTokenSet ? "token saved" : "no token yet"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow("smartthings token") {
                HStack(spacing: 8) {
                    SecureField("paste token", text: $token)
                        .arriqField()
                    TextButton(title: "save", size: 11) { save() }
                }
            }
            HStack {
                Text(note).font(Theme.font(11)).foregroundColor(Theme.fg2)
                Spacer()
            }
            .frame(height: Theme.row)

            HStack {
                TextButton(title: loading ? "loading…" : "pick your tv", size: 11) { load() }
                    .padding(.leading, -6)
                Spacer()
            }
            .frame(height: Theme.row)

            ForEach(devices) { d in
                let selected = model.settings.smartThingsDeviceID == d.id
                HStack {
                    TextButton(title: d.label.lowercased(), size: 11,
                               color: selected ? Theme.fg : Theme.fg2) {
                        model.settings.smartThingsDeviceID = d.id
                    }
                    .padding(.leading, -6)
                    Spacer()
                }
            }

            SettingRow("tv scene") {
                ArriqSwitch(isOn: $model.settings.tvSceneEnabled, label: "tv scene")
            }
            SettingRow("tv scene link") {
                TextField("paste youtube link", text: $model.settings.tvSceneLink)
                    .arriqField()
            }
            if !model.settings.tvSceneLink.isEmpty && YouTubeLink.videoID(from: model.settings.tvSceneLink) == nil {
                HStack {
                    Text("not a youtube link").font(Theme.font(11)).foregroundColor(Theme.fg2)
                    Spacer()
                }
                .frame(height: Theme.row)
            }
            SettingRow("tv address") {
                TextField("192.168.x.x", text: tvAddressBinding)
                    .arriqField()
            }
        }
    }

    private var tvAddressBinding: Binding<String> {
        Binding(get: { model.settings.tvIP ?? "" },
                set: { v in
                    let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.settings.tvIP = t.isEmpty ? nil : t
                })
    }

    private func save() {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        model.setSmartThingsToken(value)
        token = ""
        saved = true
    }

    private func load() {
        loading = true
        Task {
            let list = await model.listSmartThingsDevices()
            devices = list
            loading = false
        }
    }
}

/// philips hue: the bridge (found on the local network or typed), one-time pairing, then a room or light.
/// the key the bridge hands out goes straight to the keychain; this view never sees it.
private struct HueControls: View {
    @ObservedObject var model: AppModel
    @State private var found: [(ip: String, name: String)] = []
    @State private var finding = false
    @State private var pairing = false
    @State private var pairNote: String?
    @State private var targets: [HueTarget] = []
    @State private var loading = false

    private var note: String {
        if let pairNote { return pairNote }
        if model.settings.hueBridgeIP == nil { return "find your bridge, or type its address" }
        return model.snapshot.hueKeySet ? "paired" : "press the round button on the bridge, then pair"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow("bridge") {
                HStack(spacing: 8) {
                    TextField("192.168.x.x", text: bridgeBinding).arriqField()
                    TextButton(title: finding ? "finding…" : "find", size: 11) { find() }
                }
            }
            ForEach(found, id: \.ip) { b in
                HStack {
                    TextButton(title: "\(b.name) · \(b.ip)", size: 11,
                               color: model.settings.hueBridgeIP == b.ip ? Theme.fg : Theme.fg2) {
                        model.settings.hueBridgeIP = b.ip
                        pairNote = nil
                    }
                    .padding(.leading, -6)
                    Spacer()
                }
            }
            HStack(spacing: 0) {
                Text(note).font(Theme.font(11)).foregroundColor(Theme.fg2).lineLimit(2)
                Spacer(minLength: 8)
                TextButton(title: pairing ? "pairing…" : "pair", size: 11) { pair() }
                    .padding(.trailing, -6)
                    .disabled(model.settings.hueBridgeIP == nil || pairing)
            }
            .frame(minHeight: Theme.row)
            HStack {
                TextButton(title: loading ? "loading…" : "pick your light", size: 11) { load() }
                    .padding(.leading, -6)
                    .disabled(!model.snapshot.hueKeySet)
                Spacer()
            }
            .frame(height: Theme.row)
            ForEach(targets) { t in
                HStack {
                    TextButton(title: t.id.hasPrefix("group:") ? "\(t.label) · room" : t.label, size: 11,
                               color: model.settings.hueTarget == t.id ? Theme.fg : Theme.fg2) {
                        model.settings.hueTarget = t.id
                    }
                    .padding(.leading, -6)
                    Spacer()
                }
            }
        }
    }

    /// postel: spaces trimmed; anything typed is kept, only a full ipv4 address is used to talk to the bridge
    private var bridgeBinding: Binding<String> {
        Binding(get: { model.settings.hueBridgeIP ?? "" },
                set: { v in
                    let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.settings.hueBridgeIP = t.isEmpty ? nil : t
                    pairNote = nil
                })
    }

    private func find() {
        finding = true
        Task {
            var list: [(ip: String, name: String)] = []
            for ip in await model.findHueBridges() {
                list.append((ip, await model.hueBridgeName(ip: ip) ?? "hue bridge"))
            }
            found = list
            if list.count == 1, model.settings.hueBridgeIP == nil { model.settings.hueBridgeIP = list[0].ip }
            pairNote = list.isEmpty ? "no bridge found · type its address" : nil
            finding = false
        }
    }

    private func pair() {
        guard let ip = model.settings.hueBridgeIP else { return }
        pairing = true
        Task {
            switch await model.pairHue(ip: ip) {
            case .key: pairNote = "paired"
            case .pressButton: pairNote = "press the round button on the bridge first"
            case .failed(let why): pairNote = why
            }
            pairing = false
        }
    }

    private func load() {
        loading = true
        Task {
            targets = await model.listHueTargets()
            if targets.isEmpty { pairNote = "no lights found · pair again" }
            loading = false
        }
    }
}

private enum PhonePlatform { case iphone, android }

private struct PhoneTab: View {
    @ObservedObject var model: AppModel
    @State private var platform: PhonePlatform = .iphone

    private let iphoneSteps = [
        "open shortcuts › automation tab › + › arrive",
        "choose your home address, any time, run immediately",
        "add action get contents of url › paste the arrive link",
        "show more › method post › request body json › add a new field: text, key a, value arrived",
        "repeat for leave: paste the leave link, value left",
        "settings › privacy › location services: shortcuts always",
        "arriq also accepts a plain text body.",
    ]

    private let androidSteps = [
        "install http shortcuts, macrodroid or tasker",
        "location trigger enter home area › http post to the arrive link, body arrived",
        "location trigger exit home area › http post to the leave link, body left",
        "allow location all the time",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                TabLabel(title: "iphone", selected: platform == .iphone) { platform = .iphone }
                Text("·").font(Theme.font(11)).foregroundColor(Theme.dim)
                TabLabel(title: "android", selected: platform == .android) { platform = .android }
                Spacer(minLength: 0)
            }
            .frame(height: Theme.row)

            heading("1  copy your two links")
            linkRow("arrive", body: "arrived")
            linkRow("leave", body: "left")
            steps

            heading("2  check the link")
            HStack {
                TextButton(title: "send test signal", size: 11) { model.sendTestSignal() }
                    .padding(.leading, -6)
                Spacer()
            }
            .frame(height: Theme.row)
            Text(liveLine)
                .font(Theme.font(11)).foregroundColor(Theme.fg2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("your location never leaves the phone. arriq only receives the words arrived and left.")
                .font(Theme.font(11)).foregroundColor(Theme.fg2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 8)
            SliderRow(title: "cooldown", value: cooldownBinding, range: 5...240, step: 5) {
                "\(Int($0)) min"
            }
            SliderRow(title: "pair window", value: pairBinding, range: 1...60) {
                "\(Int($0)) min"
            }
        }
    }

    private var stepLines: [String] { platform == .iphone ? iphoneSteps : androidSteps }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(stepLines.indices, id: \.self) { i in
                Text("\(i + 1). \(stepLines[i])")
                    .font(Theme.font(11)).foregroundColor(Theme.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, 4)
    }

    private var liveLine: String {
        if !model.snapshot.listening { return "not listening · check your internet" }
        if let t = model.snapshot.lastPhoneSignal { return "heard from phone · \(Fmt.clock(t))" }
        return "listening · waiting for the first signal"
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(Theme.font(13)).foregroundColor(Theme.fg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func linkRow(_ title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text(title).font(Theme.font(13)).foregroundColor(Theme.fg)
                Spacer(minLength: 8)
                CopyButton(text: model.phoneURL)
            }
            .frame(height: Theme.row)
            Text(model.phoneURL)
                .font(Theme.font(11)).foregroundColor(Theme.fg2)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Text("body: \(body)")
                .font(Theme.font(11)).foregroundColor(Theme.fg)
        }
        .padding(.bottom, 8)
    }

    private var cooldownBinding: Binding<Double> {
        Binding(get: { Double(model.settings.cooldownMinutes) },
                set: { model.settings.cooldownMinutes = Int($0) })
    }

    private var pairBinding: Binding<Double> {
        Binding(get: { Double(model.settings.pairWindowMinutes) },
                set: { model.settings.pairWindowMinutes = Int($0) })
    }
}

/// Copies the url and shows `copied` for 1.5s.
private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        TextButton(title: copied ? "copied" : "copy", size: 11) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                copied = false
            }
        }
    }
}

private struct HomeTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("arriq knows you are home when this laptop is on your home wifi.")
                Text("\"this network is home\" re-saves the current network.")
            }
            .font(Theme.font(11)).foregroundColor(Theme.fg2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)

            HStack {
                TextButton(title: "this network is home") { model.markHome() }
                    .padding(.leading, -6)
                Spacer()
            }
            .frame(height: Theme.row)
            SettingRow("saved") {
                Text(model.settings.homeGatewayMAC ?? "none yet")
                    .font(Theme.font(11)).foregroundColor(Theme.fg)
            }
            SettingRow("now") {
                Text(model.snapshot.gatewayMAC ?? "unknown")
                    .font(Theme.font(11)).foregroundColor(Theme.fg)
            }
            SettingRow("home / away") {
                Text(model.snapshot.macHome ? "home" : "away")
                    .font(Theme.font(11)).foregroundColor(Theme.fg)
            }
        }
    }
}

private struct LogTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if model.snapshot.log.isEmpty {
                        Text("nothing yet")
                            .font(Theme.font(11)).foregroundColor(Theme.fg2)
                    }
                    ForEach(model.snapshot.log) { line in
                        Text("\(Fmt.clockSeconds(line.time)) \(line.text)")
                            .font(Theme.font(11)).foregroundColor(Theme.fg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 12)
            }
            .onAppear {
                if let last = model.snapshot.log.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}
