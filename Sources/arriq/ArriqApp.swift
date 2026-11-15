import AppKit
import SwiftUI
import ArriqKit

/// AppKit side: menu bar only, the window opens on launch and on reopen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applicationWillFinishLaunchingSignals()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // started from the after-quit gadget: come up quietly in the menu bar, the gadget already said "starting"
        if AfterQuit.parse(CommandLine.arguments) == .app(on: true) {
            _ = AppModel.shared
        } else {
            AppModel.shared.openWindow()
        }
        #if DEBUG
        DebugSnapshot.openPopoverIfAsked()
        #endif
    }

    /// `kill` / `killall arriq` quit like the menu does, so settings save and the after-quit gadget takes over.
    private var sigterm: DispatchSourceSignal?

    func applicationWillFinishLaunchingSignals() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.openWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// One binary, two roles: `--gadget` is the after-quit desktop gadget (LaunchAgent), anything else is the app.
@main
enum Entry {
    @MainActor static func main() {
        switch AfterQuit.parse(CommandLine.arguments) {
        case .gadget: GadgetHelper.run()
        case .app: ArriqApp.main()
        }
    }
}

struct ArriqApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { AppModel.shared }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(nsImage: MenuBarIcon.image(enabled: model.settings.enabled))
            .accessibilityLabel("arriq")
    }
}
