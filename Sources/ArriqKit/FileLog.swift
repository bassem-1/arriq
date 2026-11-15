import Foundation

/// plain-text diagnostics at ~/Library/Logs/arriq/arriq.log, rotated to arriq.log.1 past 1 MB.
/// lines are timestamped and lower-case. never pass a topic, url or token: use `mask` for a topic.
public enum FileLog {
    public static let maxBytes = 1_000_000
    private static let lock = NSLock()

    public static var defaultURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/arriq/arriq.log")
    }

    /// dry runs (tests, previews) never touch the real log
    static var isDryRun: Bool { ProcessInfo.processInfo.environment["ARRIQ_DRY_RUN"] == "1" }

    /// the app's log. no-op in a dry run.
    public static func write(_ text: String, at date: Date = Date()) {
        guard !isDryRun else { return }
        append(text, at: date, to: defaultURL)
    }

    /// appends one line to `url`, creating folders and rotating first when the file is at the limit.
    static func append(_ text: String, at date: Date, to url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let line = format(text, at: date) + "\n"
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int, size >= maxBytes {
                let rotated = url.appendingPathExtension("1")
                try? fm.removeItem(at: rotated)
                try? fm.moveItem(at: url, to: rotated)
            }
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            // logging must never break the app; nothing else to do here
        }
    }

    /// "2026-11-15T10:04:05.123Z text" with the text lower-cased
    static func format(_ text: String, at date: Date) -> String {
        formatter.string(from: date) + " " + text.lowercased()
    }

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// "topic…xx": the last two characters only, never the whole topic
    public static func mask(_ topic: String) -> String {
        guard topic.count > 2 else { return "topic…" }
        return "topic…" + topic.suffix(2)
    }
}
