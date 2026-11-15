import Foundation

/// spotify desktop app: route audio to the speaker, open spotify, then start the pasted link over applescript.
/// the link itself is never logged.
public enum MusicDriver {
    public static func run(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: blocking(settings: settings, dryRun: dryRun))
            }
        }
    }

    static func blocking(settings: Settings, dryRun: Bool) -> DeviceOutcome {
        guard let uri = SpotifyLink.uri(from: settings.spotifyLink), let kind = SpotifyLink.kind(ofURI: uri) else {
            return fail("not a spotify link")
        }
        if dryRun {
            return DeviceOutcome(ok: true, text: "dry run: music · \(kind) · vol \(settings.musicVolume)")
        }
        guard let device = AudioRoute.outputDeviceID(matchingAddress: settings.speakerAddress),
              AudioRoute.setDefaultOutput(device) else {
            return fail("speaker not an output yet")
        }
        guard run("/usr/bin/open", ["-g", "-b", "com.spotify.client"]).status == 0 else {
            return fail("spotify not installed")
        }
        let deadline = Date().addingTimeInterval(15)
        var ready = false
        var lastErr = ""
        while Date() < deadline {
            let r = run("/usr/bin/osascript", ["-e", "tell application \"Spotify\" to player state"])
            if r.status == 0 { ready = true; break }
            lastErr = r.err
            if lastErr.contains("-1743") { break }
            Thread.sleep(forTimeInterval: 1)
        }
        if !ready { return failure(reason(osascriptStderr: lastErr)) }
        let r = run("/usr/bin/osascript", ["-e", script(uri: uri, volume: settings.musicVolume, shuffle: settings.musicShuffle)])
        guard r.status == 0 else { return failure(reason(osascriptStderr: r.err)) }
        return DeviceOutcome(ok: true, text: "music on · \(kind)")
    }

    public static func pause(dryRun: Bool) async -> DeviceOutcome {
        if dryRun { return DeviceOutcome(ok: true, text: "dry run: music paused") }
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let r = run("/usr/bin/osascript", ["-e", pauseScript])
                cont.resume(returning: r.status == 0
                    ? DeviceOutcome(ok: true, text: "music paused")
                    : failure(reason(osascriptStderr: r.err)))
            }
        }
    }

    static let pauseScript = """
    if application "Spotify" is running then
    tell application "Spotify" to pause
    end if
    """

    static func script(uri: String, volume: Int, shuffle: Bool) -> String {
        let v = min(max(volume, 0), 100)
        return """
        tell application "Spotify"
        set sound volume to \(v)
        set shuffling to \(shuffle ? "true" : "false")
        play track "\(uri)"
        end tell
        """
    }

    static func reason(osascriptStderr: String) -> String {
        osascriptStderr.contains("-1743") ? "not allowed to control spotify" : "spotify did not respond"
    }

    private static func failure(_ reason: String) -> DeviceOutcome {
        var o = fail(reason)
        if reason == "not allowed to control spotify" { o.hint = "system settings › privacy › automation › arriq" }
        return o
    }

    private static func fail(_ reason: String) -> DeviceOutcome {
        DeviceOutcome(ok: false, text: "music failed · \(reason)")
    }

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        do { try p.run() } catch { return (-1, "") }
        let data = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
