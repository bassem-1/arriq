import Foundation

/// the desktop gadget after arriq quits: a LaunchAgent runs this same binary with `--gadget` from a nested helper
/// bundle (`Contents/Helpers/arriq gadget.app`, its own bundle id). a bundled binary registers with launch services
/// under its bundle's id, so a helper inside the main bundle id would swallow `open -a arriq` and would count
/// itself as "arriq is running". paths and the launchctl runner are parameters, so all of this is testable.
public enum AfterQuit {
    public static let label = "io.github.arriq.gadget"
    public static let appBundleID = "io.github.arriq"
    public static let helperBundleID = "io.github.arriq.gadget"
    public static let helperName = "arriq gadget.app"

    public enum Launch: Equatable, Sendable {
        case gadget              // `--gadget`: only the desktop gadget, no engine, no menu bar
        case app(on: Bool)       // the app; `--on` switches arriq on (the gadget's click)
    }

    public static func parse(_ argv: [String]) -> Launch {
        argv.contains("--gadget") ? .gadget : .app(on: argv.contains("--on"))
    }

    /// the helper's gadget shows only while arriq is not running, the gadget is on and the setting is on
    public static func shouldShow(appRunning: Bool, gadgetEnabled: Bool, afterQuit: Bool) -> Bool {
        !appRunning && gadgetEnabled && afterQuit
    }

    /// the agent is wanted when both settings are on and the app ships the helper (a `swift run` build does not)
    public static func wanted(_ s: Settings, helperExists: Bool) -> Bool {
        s.gadgetEnabled && s.gadgetAfterQuit && helperExists
    }

    public static func helperApp(inApp appPath: String) -> String {
        (appPath as NSString).appendingPathComponent("Contents/Helpers/\(helperName)")
    }

    public static func helperExecutable(inApp appPath: String) -> String {
        (helperApp(inApp: appPath) as NSString).appendingPathComponent("Contents/MacOS/arriq")
    }

    /// the main app, from inside the helper: <arriq.app>/Contents/Helpers/<helper>.app
    public static func mainApp(fromHelper helperPath: String) -> String {
        var p = helperPath as NSString
        for _ in 0..<3 { p = p.deletingLastPathComponent as NSString }
        return p as String
    }

    public static var plistPath: String {
        NSString(string: "~/Library/LaunchAgents/\(label).plist").expandingTildeInPath
    }

    public static var logPath: String {
        NSString(string: "~/Library/Logs/arriq-gadget.log").expandingTildeInPath
    }

    /// KeepAlive only after a crash: "quit gadget" (exit 0) stays quit until arriq's next quit or the next login
    public static func plist(executable: String, log: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable, "--gadget"],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "StandardOutPath": log,
            "StandardErrorPath": log,
        ]
    }

    /// file only. true when the file changed
    @discardableResult
    public static func writePlist(_ on: Bool, executable: String, path: String = plistPath, log: String = logPath) -> Bool {
        let fm = FileManager.default
        guard on else {
            guard fm.fileExists(atPath: path) else { return false }
            return (try? fm.removeItem(atPath: path)) != nil
        }
        let wanted = plist(executable: executable, log: log) as NSDictionary
        if let current = NSDictionary(contentsOfFile: path), current == wanted { return false }
        try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard let data = try? PropertyListSerialization.data(fromPropertyList: wanted, format: .xml, options: 0) else {
            return false
        }
        return fm.createFile(atPath: path, contents: data)
    }

    // MARK: launchctl

    public typealias Runner = ([String]) -> Int32

    public static let launchctl: Runner = { args in
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return 1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    public static var domain: String { "gui/\(getuid())" }

    public static func isLoaded(run: Runner = launchctl) -> Bool {
        run(["print", "\(domain)/\(label)"]) == 0
    }

    /// the setting changed or the app started. on: write the plist; the agent loads at login or when arriq quits,
    /// and a running helper just stays hidden. off: stop the helper and delete the plist.
    public static func sync(_ on: Bool, executable: String, path: String = plistPath, run: Runner = launchctl) {
        if on {
            writePlist(true, executable: executable, path: path)
        } else {
            if isLoaded(run: run) { _ = run(["bootout", "\(domain)/\(label)"]) }
            writePlist(false, executable: executable, path: path)
        }
    }

    /// arriq is quitting: make sure the helper is loaded and running so the gadget stays on the desktop.
    @discardableResult
    public static func onQuit(_ on: Bool, path: String = plistPath, run: Runner = launchctl) -> Bool {
        guard on, FileManager.default.fileExists(atPath: path) else { return false }
        if !isLoaded(run: run) { _ = run(["bootstrap", domain, path]) }
        _ = run(["kickstart", "\(domain)/\(label)"])  // no -k: starts it when idle, leaves a running one alone
        return true
    }
}
