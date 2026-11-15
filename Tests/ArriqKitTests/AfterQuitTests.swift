import Foundation
import Testing
@testable import ArriqKit

// the after-quit gadget: argument parsing, when it shows, the LaunchAgent plist and the launchctl calls.

@Test func argumentsPickTheRole() {
    #expect(AfterQuit.parse(["/x/arriq"]) == .app(on: false))
    #expect(AfterQuit.parse(["/x/arriq", "--on"]) == .app(on: true))
    #expect(AfterQuit.parse(["/x/arriq", "--gadget"]) == .gadget)
    // finder adds -psn_ style junk on some systems; it never changes the role
    #expect(AfterQuit.parse(["/x/arriq", "-psn_0_12345"]) == .app(on: false))
}

@Test func gadgetShowsOnlyWhenArriqIsGoneAndBothSettingsAreOn() {
    #expect(AfterQuit.shouldShow(appRunning: false, gadgetEnabled: true, afterQuit: true))
    #expect(!AfterQuit.shouldShow(appRunning: true, gadgetEnabled: true, afterQuit: true))
    #expect(!AfterQuit.shouldShow(appRunning: false, gadgetEnabled: false, afterQuit: true))
    #expect(!AfterQuit.shouldShow(appRunning: false, gadgetEnabled: true, afterQuit: false))
}

@Test func agentIsWantedOnlyWithTheHelperAndBothSettings() {
    var s = Settings()
    #expect(s.gadgetAfterQuit)  // default on
    #expect(AfterQuit.wanted(s, helperExists: true))
    #expect(!AfterQuit.wanted(s, helperExists: false))
    s.gadgetAfterQuit = false
    #expect(!AfterQuit.wanted(s, helperExists: true))
    s.gadgetAfterQuit = true
    s.gadgetEnabled = false
    #expect(!AfterQuit.wanted(s, helperExists: true))
}

@Test func helperPathsRoundTrip() {
    let app = "/Applications/arriq.app"
    #expect(AfterQuit.helperApp(inApp: app) == "/Applications/arriq.app/Contents/Helpers/arriq gadget.app")
    #expect(AfterQuit.helperExecutable(inApp: app)
        == "/Applications/arriq.app/Contents/Helpers/arriq gadget.app/Contents/MacOS/arriq")
    #expect(AfterQuit.mainApp(fromHelper: AfterQuit.helperApp(inApp: app)) == app)
}

@Test func plistRunsTheHelperInGadgetModeAndRestartsOnlyAfterACrash() {
    let p = AfterQuit.plist(executable: "/a/arriq", log: "/l.log")
    #expect(p["Label"] as? String == "io.github.arriq.gadget")
    #expect(p["ProgramArguments"] as? [String] == ["/a/arriq", "--gadget"])
    #expect(p["RunAtLoad"] as? Bool == true)
    #expect((p["KeepAlive"] as? [String: Bool])?["SuccessfulExit"] == false)
}

private func tempPlist() -> String {
    NSTemporaryDirectory() + "arriq-test-\(UUID().uuidString)/agent.plist"
}

@Test func writePlistIsIdempotentAndRemovable() {
    let path = tempPlist()
    #expect(AfterQuit.writePlist(true, executable: "/a/arriq", path: path, log: "/l.log"))
    #expect(!AfterQuit.writePlist(true, executable: "/a/arriq", path: path, log: "/l.log"))  // unchanged
    #expect(AfterQuit.writePlist(true, executable: "/b/arriq", path: path, log: "/l.log"))   // app moved
    let back = NSDictionary(contentsOfFile: path)
    #expect((back?["ProgramArguments"] as? [String])?.first == "/b/arriq")
    #expect(AfterQuit.writePlist(false, executable: "", path: path))
    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(!AfterQuit.writePlist(false, executable: "", path: path))  // already gone
}

private final class Calls: @unchecked Sendable {
    var all: [[String]] = []
    var loaded = false
    func runner() -> AfterQuit.Runner {
        { args in
            self.all.append(args)
            if args.first == "print" { return self.loaded ? 0 : 113 }
            return 0
        }
    }
    var verbs: [String] { all.compactMap(\.first) }
}

@Test func syncOffStopsALoadedHelperAndDeletesThePlist() {
    let path = tempPlist()
    AfterQuit.writePlist(true, executable: "/a/arriq", path: path)
    let calls = Calls()
    calls.loaded = true
    AfterQuit.sync(false, executable: "/a/arriq", path: path, run: calls.runner())
    #expect(calls.verbs == ["print", "bootout"])
    #expect(!FileManager.default.fileExists(atPath: path))
}

@Test func syncOnOnlyWritesThePlistAndNeverStartsTheHelperWhileArriqRuns() {
    let path = tempPlist()
    let calls = Calls()
    AfterQuit.sync(true, executable: "/a/arriq", path: path, run: calls.runner())
    #expect(calls.verbs.isEmpty)
    #expect(FileManager.default.fileExists(atPath: path))
}

@Test func onQuitBootstrapsWhenNeededThenKickstarts() {
    let path = tempPlist()
    AfterQuit.writePlist(true, executable: "/a/arriq", path: path)
    let cold = Calls()
    #expect(AfterQuit.onQuit(true, path: path, run: cold.runner()))
    #expect(cold.verbs == ["print", "bootstrap", "kickstart"])
    #expect(cold.all.last?.contains("-k") == false)  // never restarts a running helper

    let warm = Calls()
    warm.loaded = true
    #expect(AfterQuit.onQuit(true, path: path, run: warm.runner()))
    #expect(warm.verbs == ["print", "kickstart"])
}

@Test func onQuitDoesNothingWhenOffOrNotInstalled() {
    let calls = Calls()
    #expect(!AfterQuit.onQuit(false, path: tempPlist(), run: calls.runner()))
    #expect(!AfterQuit.onQuit(true, path: tempPlist(), run: calls.runner()))  // no plist written
    #expect(calls.all.isEmpty)
}

@Test func afterQuitSettingDecodesTolerantly() throws {
    let missing = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
    #expect(missing.gadgetAfterQuit)
    let off = try JSONDecoder().decode(Settings.self, from: Data(#"{"gadgetAfterQuit": false}"#.utf8))
    #expect(!off.gadgetAfterQuit)
    let junk = try JSONDecoder().decode(Settings.self, from: Data(#"{"gadgetAfterQuit": "nope"}"#.utf8))
    #expect(junk.gadgetAfterQuit)
    let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(off))
    #expect(!back.gadgetAfterQuit)
}
