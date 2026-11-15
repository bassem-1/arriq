import Foundation

/// samsung tv through smartthings: POST a switch-on command to the chosen device.
public enum TVDriver {
    /// why the tv cannot run yet; nil when it is set up
    public static func notSetUpReason(settings: Settings, tokenSet: Bool) -> String? {
        if !tokenSet { return "add a smartthings token" }
        if settings.smartThingsDeviceID == nil { return "pick your tv" }
        return nil
    }

    public static func run(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        if dryRun {
            if wantsScene(settings) { return DeviceOutcome(ok: true, text: "dry run: tv on · scene") }
            return DeviceOutcome(ok: true, text: "dry run: tv on · \(settings.smartThingsDeviceID ?? "none")")
        }
        guard let deviceID = settings.smartThingsDeviceID else {
            return DeviceOutcome(ok: false, text: "tv failed · not set up")
        }
        // the secret is read here, only when the tv actually runs, never at launch
        switch TokenStore.read() {
        case .absent:
            return DeviceOutcome(ok: false, text: "tv failed · not set up")
        case .denied:
            return DeviceOutcome(ok: false, text: "tv failed · token access denied")
        case .token(let token):
            if let reason = await SmartThingsAPI.sendOn(deviceID: deviceID, token: token) {
                return DeviceOutcome(ok: false, text: "tv failed · \(reason)",
                                     hint: SmartThingsAPI.hint(forReason: reason))
            }
            guard settings.tvSceneEnabled, !settings.tvSceneLink.isEmpty else {
                return DeviceOutcome(ok: true, text: "tv on")
            }
            guard let videoID = YouTubeLink.videoID(from: settings.tvSceneLink) else {
                return DeviceOutcome(ok: true, text: "tv on · not a youtube link")
            }
            return await scene(settings: settings, deviceID: deviceID, token: token, videoID: videoID)
        }
    }

    public static func off(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        if dryRun {
            return DeviceOutcome(ok: true, text: "dry run: tv off · \(settings.smartThingsDeviceID ?? "none")")
        }
        guard let deviceID = settings.smartThingsDeviceID, case .token(let token) = TokenStore.read() else {
            return DeviceOutcome(ok: false, text: "tv off failed · not set up")
        }
        if let reason = await SmartThingsAPI.send(deviceID: deviceID, token: token, capability: "switch", command: "off") {
            return DeviceOutcome(ok: false, text: "tv off failed · \(reason)", hint: SmartThingsAPI.hint(forReason: reason))
        }
        return DeviceOutcome(ok: true, text: "tv off")
    }

    static func wantsScene(_ s: Settings) -> Bool {
        s.tvSceneEnabled && !s.tvSceneLink.isEmpty
    }

    /// dial first when the tv address is known, then the smartthings app launch; both retry while the tv boots
    static func scene(settings: Settings, deviceID: String, token: String, videoID: String) async -> DeviceOutcome {
        let ip = settings.tvIP?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !ip.isEmpty, let req = TVScene.dialRequest(ip: ip, videoID: videoID) {
            for wait in TVScene.backoff {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                if let (_, resp) = try? await URLSession.shared.data(for: req),
                   let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) {
                    return DeviceOutcome(ok: true, text: "tv on · scene started")
                }
            }
        }
        for wait in TVScene.backoff {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            let failure = await SmartThingsAPI.send(deviceID: deviceID, token: token, capability: "custom.launchapp",
                                                    command: "launchApp", arguments: [TVScene.youtubeAppID])
            if failure == nil {
                return DeviceOutcome(ok: true, text: "tv on · youtube opened",
                                     hint: ip.isEmpty ? "add tv address to play the video" : nil)
            }
        }
        return DeviceOutcome(ok: true, text: "tv on · scene failed")
    }
}
