import Foundation

public struct NtfyMessage: Equatable, Sendable {
    public let id: String
    public let time: Date
    public let body: String
    public init(id: String, time: Date, body: String) {
        self.id = id; self.time = time; self.body = body
    }
}

private struct NtfyWire: Decodable {
    let id: String?
    let event: String?
    let time: Double?
    let message: String?
}

/// one line of ntfy's json stream. nil for open/keepalive events, junk or missing fields.
public func parseNtfyLine(_ line: String) -> NtfyMessage? {
    guard let data = line.data(using: .utf8),
          let wire = try? JSONDecoder().decode(NtfyWire.self, from: data),
          wire.event == "message",
          let id = wire.id, !id.isEmpty,
          let body = wire.message,
          let time = wire.time
    else { return nil }
    return NtfyMessage(id: id, time: Date(timeIntervalSince1970: time), body: body)
}

/// what a phone body means. plain words (trimmed, lower-cased, optionally in double quotes) win;
/// a json body ({...} or [...]) is searched for its strings and keys; as a last resort a whole word
/// of arrived, left or test anywhere in the body counts. a body that yields two different signals is nil.
public enum PhoneSignal: Equatable, Sendable {
    case arrived, left, test

    public static func classify(_ body: String) -> PhoneSignal? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = exact(trimmed) { return s }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            if let json = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) {
                var strings: [String] = []
                collectStrings(json, into: &strings)
                let signals = Set(strings.compactMap(exact))
                if signals.count == 1 { return signals.first }
                if signals.count > 1 { return nil }
            }
        }
        let words = trimmed.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let signals = Set(words.compactMap(named))
        return signals.count == 1 ? signals.first : nil
    }

    /// a single whole string: trimmed, optional surrounding double quotes removed, then matched exactly.
    private static func exact(_ s: String) -> PhoneSignal? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") {
            t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return named(t)
    }

    private static func named(_ s: String) -> PhoneSignal? {
        switch s.lowercased() {
        case "arrived": return .arrived
        case "left": return .left
        case "test": return .test
        default: return nil
        }
    }

    private static func collectStrings(_ v: Any, into out: inout [String]) {
        if let s = v as? String {
            out.append(s)
        } else if let d = v as? [String: Any] {
            for (k, val) in d {
                out.append(k)
                collectStrings(val, into: &out)
            }
        } else if let a = v as? [Any] {
            for item in a { collectStrings(item, into: &out) }
        }
    }
}

/// why a message was kept or dropped
public enum NtfyVerdict: Equatable, Sendable {
    case accept, stale, duplicate
}

/// drops stale messages (older than maxAge) and ids seen before; remembers the last `capacity` ids.
public struct NtfyFilter: Sendable {
    public let maxAge: TimeInterval
    public let capacity: Int
    private var order: [String] = []
    private var seen: Set<String> = []

    public init(maxAge: TimeInterval = 300, capacity: Int = 256) {
        self.maxAge = maxAge
        self.capacity = capacity
    }

    public mutating func accept(_ m: NtfyMessage, now: Date) -> Bool {
        verdict(m, now: now) == .accept
    }

    public mutating func verdict(_ m: NtfyMessage, now: Date) -> NtfyVerdict {
        guard now.timeIntervalSince(m.time) <= maxAge else { return .stale }
        guard !seen.contains(m.id) else { return .duplicate }
        seen.insert(m.id)
        order.append(m.id)
        if order.count > capacity {
            seen.remove(order.removeFirst())
        }
        return .accept
    }
}

public enum NtfyBackoff {
    /// 1s, 2s, 4s … capped at 60s; n is the number of failures in a row
    public static func delay(afterFailures n: Int) -> TimeInterval {
        min(60, pow(2, Double(max(0, n))))
    }
}

/// numbers each stream attempt. a replaced or stopped attempt must not change the listening flag.
public final class NtfyGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0

    public init() {}

    /// starts a new attempt and returns its number; every older attempt becomes stale
    public func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        current += 1
        return current
    }

    public func isCurrent(_ attempt: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return attempt == current
    }
}

/// streaming subscription to https://ntfy.sh/<topic>/json. reconnects with backoff while running.
public final class NtfyClient: @unchecked Sendable {
    private let session: URLSession
    private var task: Task<Void, Never>?
    private let generation = NtfyGeneration()

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        session = URLSession(configuration: cfg)
    }

    public static func streamURL(topic: String) -> URL? {
        URL(string: "https://ntfy.sh/\(topic)/json?since=5m")
    }

    public func start(topic: String,
                      onListening: @escaping @Sendable (Bool) -> Void,
                      onMessage: @escaping @Sendable (NtfyMessage) -> Void) {
        stop()
        let attempt = generation.next()
        let masked = FileLog.mask(topic)
        guard let url = Self.streamURL(topic: topic) else {
            FileLog.write("ntfy not started · bad topic · \(masked)")
            onListening(false)
            return
        }
        let session = self.session
        let generation = self.generation
        task = Task {
            var failures = 0
            var tries = 0
            while !Task.isCancelled {
                tries += 1
                var gotLine = false
                var lines = 0
                FileLog.write("ntfy connect · try \(tries) · \(masked)")
                do {
                    let (bytes, response) = try await session.bytes(from: url)
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    FileLog.write("ntfy http \(code) · \(masked)")
                    guard code == 200 else {
                        throw URLError(.badServerResponse)
                    }
                    if generation.isCurrent(attempt) { onListening(true) }
                    FileLog.write("ntfy listening · true")
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        gotLine = true
                        lines += 1
                        if let m = parseNtfyLine(line) { onMessage(m) }
                    }
                    FileLog.write("ntfy stream ended · lines \(lines)")
                } catch {
                    // a cancelled attempt was replaced or stopped on purpose; it reports nothing
                    if Task.isCancelled { break }
                    let e = error as NSError
                    FileLog.write("ntfy error · \(e.domain) \(e.code) · \(e.localizedDescription)")
                }
                if Task.isCancelled { break }
                if generation.isCurrent(attempt) { onListening(false) }
                FileLog.write("ntfy listening · false")
                failures = gotLine ? 0 : failures + 1
                let wait = NtfyBackoff.delay(afterFailures: failures)
                FileLog.write("ntfy retry in \(Int(wait))s · failures \(failures)")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    public func stop() {
        _ = generation.next()
        task?.cancel()
        task = nil
    }
}
