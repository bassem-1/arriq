import AppKit
import Combine
import SwiftUI
import ArriqKit

/// `arriq --gadget`, started by the LaunchAgent from the nested helper bundle: keeps the desktop gadget on screen
/// while arriq itself is not running. No engine, no network, no bluetooth, no timers: it only wakes when the
/// running-apps list changes. Click = start arriq switched on.
@MainActor
final class GadgetHelper: NSObject, NSApplicationDelegate {
    private static var retained: GadgetHelper?

    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let helper = GadgetHelper()
        retained = helper  // NSApplication holds its delegate weakly
        app.delegate = helper
        app.run()
    }

    private var settings = SettingsStore.load()
    private let face = HelperFace()
    private let pulses = PassthroughSubject<Void, Never>()
    private var panel: GadgetPanel?
    private var appsObservation: NSKeyValueObservation?
    private var screensObserver: NSObjectProtocol?
    private var appRunning = false
    private var shown: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = SettingsStore.load()
        guard settings.gadgetAfterQuit else {
            log("gadget after quit is off: exiting")
            exit(0)
        }
        // KVO, not didLaunch / didTerminate: those are never posted for LSUIElement (menu bar) apps
        appsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.runningAppsChanged() }
        }
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let panel = self?.panel else { return }
                panel.setFrameOrigin(GadgetGeometry.clamp(panel.frame.origin))
            }
        }
        appRunning = Self.isAppRunning()
        evaluate()
    }

    static func isAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: AfterQuit.appBundleID).isEmpty
    }

    private func runningAppsChanged() {
        let running = Self.isAppRunning()
        guard running != appRunning else { return }
        appRunning = running
        evaluate()
    }

    private func evaluate() {
        settings = SettingsStore.load()  // arriq may have moved the gadget or changed float while it ran
        let show = AfterQuit.shouldShow(appRunning: appRunning, gadgetEnabled: settings.gadgetEnabled,
                                        afterQuit: settings.gadgetAfterQuit)
        if show {
            face.caption = "click to start"
            let p = panel ?? makePanel()
            p.level = GadgetGeometry.level(floats: settings.gadgetFloats)
            p.setFrameOrigin(GadgetGeometry.origin(settings.gadgetOrigin))
            p.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
        if show != shown {
            shown = show
            log(show ? "gadget shown" : appRunning ? "gadget hidden · arriq is running" : "gadget hidden")
        }
    }

    private func makePanel() -> GadgetPanel {
        let p = GadgetGeometry.makePanel()
        let host = NSHostingView(rootView: HelperGadgetView(face: face, pulses: pulses))
        host.frame = NSRect(origin: .zero, size: GadgetGeometry.size)
        p.contentView = host
        p.onClick = { [weak self] in self?.start() }
        p.onMoved = { [weak self] origin in self?.moved(to: origin) }
        p.menuBuilder = { [weak self] in self?.buildMenu() ?? NSMenu() }
        panel = p
        return p
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        menu.addItem(ActionItem("start arriq") { [weak self] in self?.start() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("hide gadget") { [weak self] in self?.hide() })
        menu.addItem(ActionItem("quit gadget") { NSApp.terminate(nil) })
        return menu
    }

    /// Opens arriq switched on. The pulse answers the click in the same frame; the caption says what happens next.
    private func start() {
        pulses.send()
        face.caption = "starting…"
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--on"]
        config.activates = false
        guard let url = Self.appURL() else {
            face.caption = "arriq not found"
            log("start: arriq.app not found")
            return
        }
        log("start arriq · \(url.path)")
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.face.caption = "could not start"
                self?.log("start failed · \(error.localizedDescription.lowercased())")
            }
        }
    }

    /// The app this helper ships inside, else wherever launch services knows arriq from.
    static func appURL() -> URL? {
        let outer = AfterQuit.mainApp(fromHelper: Bundle.main.bundlePath)
        if Bundle(path: outer)?.bundleIdentifier == AfterQuit.appBundleID { return URL(fileURLWithPath: outer) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: AfterQuit.appBundleID)
    }

    /// "hide gadget" turns the after-quit gadget off for good (arriq › window footer turns it back on).
    private func hide() {
        log("hide gadget: gadget after quit off")
        var fresh = SettingsStore.load()
        fresh.gadgetAfterQuit = false
        SettingsStore.save(fresh)
        // the plist first, then bootout: bootout ends this process
        AfterQuit.writePlist(false, executable: "")
        _ = AfterQuit.launchctl(["bootout", "\(AfterQuit.domain)/\(AfterQuit.label)"])
        exit(0)
    }

    private func moved(to origin: CGPoint) {
        let c = GadgetGeometry.clamp(origin)
        panel?.setFrameOrigin(c)
        var fresh = SettingsStore.load()  // only the origin is written, onto a fresh copy of the file
        fresh.gadgetOrigin = [Double(c.x), Double(c.y)]
        SettingsStore.save(fresh)
    }

    private func log(_ text: String) {
        print(text)
        fflush(stdout)
    }
}

private final class HelperFace: ObservableObject {
    @Published var caption = "click to start"
}

private struct HelperGadgetView: View {
    @ObservedObject var face: HelperFace
    let pulses: PassthroughSubject<Void, Never>

    var body: some View {
        GadgetFace(state: "off", on: false, caption: face.caption, pulses: pulses)
    }
}
