import Foundation
import Network

/// philips hue through the local bridge: on, off and live brightness / colour for the chosen room or light.
/// the key is read from the keychain only when a command runs, never at launch, never logged.
public enum HueDriver {
    /// why hue cannot run yet; nil when it is set up
    public static func notSetUpReason(settings: Settings, keySet: Bool) -> String? {
        if settings.hueBridgeIP == nil { return "find your hue bridge" }
        if !keySet { return "pair your hue bridge" }
        if settings.hueTarget == nil { return "pick your hue light" }
        return nil
    }

    public static func run(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        await send(settings, on: true, verb: "on", dryRun: dryRun)
    }

    public static func off(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        await send(settings, on: false, verb: "off", dryRun: dryRun)
    }

    public static func adjust(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        await send(settings, on: nil, verb: "set", dryRun: dryRun)
    }

    static func send(_ s: Settings, on: Bool?, verb: String, dryRun: Bool) async -> DeviceOutcome {
        let target = s.hueTarget ?? "none"
        if dryRun { return DeviceOutcome(ok: true, text: "dry run: hue \(verb) · \(target)") }
        guard let ip = s.hueBridgeIP, let chosen = s.hueTarget else {
            return DeviceOutcome(ok: false, text: "hue \(verb) failed · not set up")
        }
        let key: String
        switch await readKey() {
        case .token(let k): key = k
        case .absent: return DeviceOutcome(ok: false, text: "hue \(verb) failed · pair your hue bridge")
        case .denied: return DeviceOutcome(ok: false, text: "hue \(verb) failed · key access denied")
        }
        guard let req = HueAPI.stateRequest(ip: ip, key: key, target: chosen, body: HueAPI.stateBody(s, on: on)) else {
            return DeviceOutcome(ok: false, text: "hue \(verb) failed · bad bridge address")
        }
        guard let data = await HueSession(host: ip).data(req) else {
            return DeviceOutcome(ok: false, text: "hue \(verb) failed · bridge not reachable",
                                 hint: "hue: the bridge must be on the same network as this mac")
        }
        if let reason = HueAPI.parseResult(data) {
            return DeviceOutcome(ok: false, text: "hue \(verb) failed · \(reason)")
        }
        return DeviceOutcome(ok: true, text: "hue \(verb) · \(target)")
    }

    /// keychain reads can block on a prompt: never on the main thread
    static func readKey() async -> TokenRead {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async { cont.resume(returning: TokenStore.read(TokenStore.hue)) }
        }
    }

    /// asks the bridge for a key; the bridge only says yes within 30 s of its round button being pressed
    public static func pair(ip: String) async -> HuePair {
        guard let req = HueAPI.pairRequest(ip: ip) else { return .failed("not an ip address") }
        guard let data = await HueSession(host: ip).data(req) else { return .failed("bridge not reachable") }
        return HueAPI.parsePair(data)
    }

    /// rooms and zones first, then single lights
    public static func targets(ip: String, key: String) async -> [HueTarget] {
        guard let g = HueAPI.groupsRequest(ip: ip, key: key), let l = HueAPI.lightsRequest(ip: ip, key: key) else { return [] }
        let groups = await HueSession(host: ip).data(g).map(HueAPI.parseGroups) ?? []
        let lights = await HueSession(host: ip).data(l).map(HueAPI.parseLights) ?? []
        return groups + lights
    }

    /// the bridge's name when the address answers like a hue bridge
    public static func bridgeName(ip: String) async -> String? {
        guard let req = HueAPI.configRequest(ip: ip), let data = await HueSession(host: ip).data(req) else { return nil }
        return HueAPI.parseBridgeName(data)
    }
}

/// finds hue bridges with bonjour (_hue._tcp) on the local network only; no cloud lookup.
public enum HueDiscovery {
    public static func find(timeout: TimeInterval = 4) async -> [String] {
        let endpoints = await browse(timeout: timeout)
        var ips: [String] = []
        for e in endpoints {
            if let ip = await resolve(e), !ips.contains(ip) { ips.append(ip) }
        }
        return ips
    }

    private final class Box: @unchecked Sendable {
        var endpoints: [NWEndpoint] = []
        var done = false
        let lock = NSLock()
    }

    static func browse(timeout: TimeInterval) async -> [NWEndpoint] {
        await withCheckedContinuation { cont in
            let browser = NWBrowser(for: .bonjour(type: "_hue._tcp", domain: nil), using: .tcp)
            let box = Box()
            let finish = {
                box.lock.lock(); defer { box.lock.unlock() }
                guard !box.done else { return }
                box.done = true
                browser.cancel()
                cont.resume(returning: box.endpoints)
            }
            browser.browseResultsChangedHandler = { results, _ in
                box.lock.lock(); box.endpoints = results.map(\.endpoint); box.lock.unlock()
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state { finish() }
            }
            browser.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: finish)
        }
    }

    /// connects briefly to learn the ipv4 address behind a bonjour name
    static func resolve(_ endpoint: NWEndpoint) async -> String? {
        await withCheckedContinuation { cont in
            let params = NWParameters.tcp
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
            let conn = NWConnection(to: endpoint, using: params)
            let box = Box()
            let finish: (String?) -> Void = { ip in
                box.lock.lock(); defer { box.lock.unlock() }
                guard !box.done else { return }
                box.done = true
                conn.cancel()
                cont.resume(returning: ip)
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, _)? = conn.currentPath?.remoteEndpoint {
                        let raw = "\(host)".split(separator: "%").first.map(String.init)
                        finish(raw.flatMap { NetParse.isIPv4($0) ? $0 : nil })
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled: finish(nil)
                default: break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }
}
