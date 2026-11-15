import Foundation
import Network

/// polls the default gateway's mac. every probe is reported on the main queue; the caller decides on changes.
public final class HomeDetector: @unchecked Sendable {
    public var onProbe: ((String?) -> Void)?
    private var timer: Timer?
    private var monitor: NWPathMonitor?
    private let work = DispatchQueue(label: "io.github.arriq.home", qos: .utility)

    public init() {}

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        m.start(queue: work)
        monitor = m
        refresh()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        monitor?.cancel()
        monitor = nil
    }

    public func refresh() {
        work.async { [weak self] in
            let mac = HomeDetector.probe()
            DispatchQueue.main.async { self?.onProbe?(mac) }
        }
    }

    /// blocking: default gateway, then its mac. nil without a default route or an arp entry.
    public static func probe() -> String? {
        guard let route = runTool("/sbin/route", ["-n", "get", "default"]) else {
            FileLog.write("home probe · no route output")
            return nil
        }
        guard let ip = NetParse.gateway(fromRoute: route) else {
            FileLog.write("home probe · no gateway in route output")
            return nil
        }
        guard let arp = runTool("/usr/sbin/arp", ["-n", ip]) else {
            FileLog.write("home probe · arp did not run · gateway \(ip)")
            return nil
        }
        let mac = NetParse.mac(fromARP: arp)
        FileLog.write("home probe · gateway \(ip) · mac \(mac ?? "unreadable")")
        return mac
    }

    static func runTool(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
