import Foundation

/// govee h6076 over the lan api. the socket work blocks, so it runs off the main queue.
public enum LampDriver {
    public static func run(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: blocking(settings: settings, dryRun: dryRun))
            }
        }
    }

    public static func off(settings: Settings, dryRun: Bool) async -> DeviceOutcome {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: blockingOff(settings: settings, dryRun: dryRun))
            }
        }
    }

    static func blockingOff(settings: Settings, dryRun: Bool) -> DeviceOutcome {
        if dryRun {
            return DeviceOutcome(ok: true, text: "dry run: lamp off · \(settings.lampIP ?? "scan")")
        }
        guard let sock = UDPSocket(bindPort: GoveeCommand.replyPort) else {
            return DeviceOutcome(ok: false, text: "lamp off failed · no socket")
        }
        guard let target = target(settings, sock) else {
            return DeviceOutcome(ok: false, text: "lamp off failed · not found on this wifi", hint: lampHint)
        }
        sock.send(GoveeCommand.turn(on: false), to: target, port: GoveeCommand.devicePort)
        return DeviceOutcome(ok: true, text: "lamp off · \(target)", lampIP: target)
    }

    static func blocking(settings: Settings, dryRun: Bool) -> DeviceOutcome {
        if dryRun {
            return DeviceOutcome(ok: true, text: "dry run: lamp on · \(settings.lampIP ?? "scan")")
        }
        guard let sock = UDPSocket(bindPort: GoveeCommand.replyPort) else {
            return DeviceOutcome(ok: false, text: "lamp failed · no socket")
        }
        guard let target = target(settings, sock) else {
            return DeviceOutcome(ok: false, text: "lamp failed · not found on this wifi", hint: lampHint)
        }
        let commands = [
            GoveeCommand.turn(on: true),
            GoveeCommand.brightness(settings.lampBrightness),
            GoveeCommand.warmWhite(kelvin: settings.lampKelvin),
        ]
        for c in commands {
            sock.send(c, to: target, port: GoveeCommand.devicePort)
            Thread.sleep(forTimeInterval: 0.05)
        }
        return DeviceOutcome(ok: true, text: "lamp on · \(target)", lampIP: target)
    }

    /// the cached ip when it still answers, else a fresh scan; nil when the lamp is not on this network
    static func target(_ settings: Settings, _ sock: UDPSocket) -> String? {
        // the cached ip is used when it still answers; otherwise rescan the network.
        // a cached ip on another subnet cannot answer from here, so skip straight to the scan.
        var ip: String? = nil
        if let cached = settings.lampIP {
            let local = onLocalSubnet(cached)
            let live = local && isLive(cached, sock)
            FileLog.write("lamp cached ip · local \(local) · live \(live)")
            if live { ip = cached }
        }
        if ip == nil { ip = scan(sock) }
        FileLog.write("lamp target · \(ip ?? "none") · cached \(settings.lampIP ?? "none")")
        return ip
    }

    static let lampHint = "lamp: put it on the same wifi as this mac and turn on lan control in govee home"

    /// true when the ip shares a subnet with one of this mac's ipv4 interfaces; true when none can be read
    static func onLocalSubnet(_ ip: String) -> Bool {
        var ifap: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifap) == 0, let first = ifap else { return true }
        defer { freeifaddrs(ifap) }
        var sawIPv4 = false
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, let mask = ifa.ifa_netmask,
               addr.pointee.sa_family == sa_family_t(AF_INET),
               (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                let local = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    String(cString: inet_ntoa($0.pointee.sin_addr))
                }
                let netmask = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    String(cString: inet_ntoa($0.pointee.sin_addr))
                }
                if NetParse.sameSubnet(ip, local, mask: netmask) { return true }
                sawIPv4 = true
            }
            cur = ifa.ifa_next
        }
        return !sawIPv4
    }

    static func isLive(_ ip: String, _ sock: UDPSocket) -> Bool {
        guard NetParse.isIPv4(ip) else { return false }
        sock.send(GoveeCommand.devStatus(), to: ip, port: GoveeCommand.devicePort)
        guard let reply = sock.receive(timeout: 2) else { return false }
        return reply.1 == ip
    }

    static func scan(_ sock: UDPSocket) -> String? {
        sock.send(GoveeCommand.scan(), to: GoveeCommand.multicastIP, port: GoveeCommand.scanPort)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            guard let reply = sock.receive(timeout: deadline.timeIntervalSinceNow),
                  let ip = GoveeCommand.scanIP(from: reply.0) else { continue }
            return ip
        }
        return nil
    }
}
