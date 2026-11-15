import AppKit
import Combine
import SwiftUI
import ArriqKit

enum InspectorTab: String, CaseIterable, Identifiable {
    case devices, phone, home, log
    var id: String { rawValue }
}

extension DeviceKind {
    var uiTitle: String {
        switch self {
        case .lamp: return "lamp"
        case .speaker: return "speaker"
        case .tv: return "tv"
        }
    }
}

/// Lower-case time strings shared by the window, popover and gadget.
enum Fmt {
    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let hms: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func clock(_ d: Date) -> String { hm.string(from: d) }
    static func clockSeconds(_ d: Date) -> String { hms.string(from: d) }

    /// mm:ss left until a deadline.
    static func countdown(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return "\(pad(s / 60)):\(pad(s % 60))"
    }

    private static func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

/// One model for the app delegate, popover, window and gadget, so no state is duplicated.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    /// ARRIQ_DRY_RUN=1: the app runs for preview and nothing touches the network or devices.
    static let dryRun = ProcessInfo.processInfo.environment["ARRIQ_DRY_RUN"] == "1"

    @Published var settings: ArriqKit.Settings
    @Published private(set) var snapshot = EngineSnapshot.initial
    /// Window-only state.
    @Published var tab: InspectorTab = .devices
    @Published var device: DeviceKind = .lamp
    @Published private(set) var launchAtLogin: Bool
    @Published var notice: String?

    /// Not @Published: pulses are rare, but they must not re-render every observer.
    let pulses = PassthroughSubject<Void, Never>()
    let engine = ArriqEngine()

    private var gadget: GadgetController?
    private var bag = Set<AnyCancellable>()
    private lazy var mainWindow = MainWindowController(model: self)

    var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "v\($0)" } ?? "dev"
    }

    init() {
        var loaded = SettingsStore.load()
        // started by the after-quit gadget's click: arrive switched on
        if AfterQuit.parse(CommandLine.arguments) == .app(on: true) { loaded.enabled = true }
        settings = loaded
        launchAtLogin = LaunchAtLogin.isEnabled

        // engine callbacks arrive on the main queue; hop onto the main actor to be explicit
        engine.onChange = { [weak self] snap in
            Task { @MainActor in self?.snapshot = snap }
        }
        engine.onSettingsChange = { [weak self] incoming in
            Task { @MainActor in self?.adopt(incoming) }
        }
        engine.onFire = { [weak self] in
            Task { @MainActor in self?.pulses.send() }
        }
        engine.apply(loaded)

        $settings.dropFirst()
            .sink { [weak self] s in self?.engine.apply(s) }
            .store(in: &bag)
        $settings.dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { SettingsStore.save($0) }
            .store(in: &bag)
        // only a bundled arriq (one that ships the helper) manages the agent, so a `swift run` build never
        // touches the installed app's LaunchAgent
        if FileManager.default.isExecutableFile(atPath: AppModel.helperExecutable) {
            $settings
                .map { AfterQuit.wanted($0, helperExists: true) }
                .removeDuplicates()
                .sink { AfterQuit.sync($0, executable: AppModel.helperExecutable) }
                .store(in: &bag)
        }
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                SettingsStore.save(self.settings)
                self.engine.stop()
                if FileManager.default.isExecutableFile(atPath: AppModel.helperExecutable) {
                    AfterQuit.onQuit(AfterQuit.wanted(self.settings, helperExists: true))
                }
            }
            .store(in: &bag)

        if !AppModel.dryRun { engine.start() }
        gadget = GadgetController(model: self)
    }

    func openWindow() { mainWindow.show() }

    func setting(_ kind: DeviceKind) -> DeviceSetting { settings.setting(for: kind) }

    func updateDevice(_ kind: DeviceKind, _ change: (inout DeviceSetting) -> Void) {
        switch kind {
        case .lamp: change(&settings.lamp)
        case .speaker: change(&settings.speaker)
        case .tv: change(&settings.tv)
        }
    }

    func status(_ kind: DeviceKind) -> DeviceStatus {
        switch kind {
        case .lamp: return snapshot.lamp
        case .speaker: return snapshot.speaker
        case .tv: return snapshot.tv
        }
    }

    static let helperExecutable = AfterQuit.helperExecutable(inApp: Bundle.main.bundlePath)

    func fireNow() { engine.fireNow() }
    func turnOff(_ kind: DeviceKind) { engine.turnOff(kind) }
    func turnOffAll() { engine.turnOffAll() }
    func test(_ kind: DeviceKind) { engine.test(kind) }
    func testMusic() { engine.testMusic() }
    func sendTestSignal() { engine.sendTestSignal() }

    func markHome() {
        if let mac = engine.markHome() {
            flash("saved \(mac) as home")
        } else {
            flash("no gateway found")
        }
    }

    func setSmartThingsToken(_ token: String) { engine.setSmartThingsToken(token) }
    func listSmartThingsDevices() async -> [SmartThingsDevice] { await engine.listSmartThingsDevices() }
    var phoneURL: String { engine.phoneURL(for: settings) }

    func setLaunchAtLogin(_ on: Bool) {
        let message: String? = LaunchAtLogin.set(on)
        launchAtLogin = LaunchAtLogin.isEnabled
        if let message { flash(message) }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("copied")
    }

    /// Footer note that clears itself after two seconds.
    func flash(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.notice == text { self.notice = nil }
        }
    }

    func quit() {
        SettingsStore.save(settings)
        engine.stop()
        NSApp.terminate(nil)
    }

    private func adopt(_ incoming: ArriqKit.Settings) {
        if incoming != settings { settings = incoming }
    }
}
