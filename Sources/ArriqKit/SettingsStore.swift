import Foundation

/// settings file at ~/Library/Application Support/arriq/settings.json. tolerant both ways.
public enum SettingsStore {
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("arriq", isDirectory: true).appendingPathComponent("settings.json")
    }

    /// missing or unreadable file gives defaults
    public static func load(from url: URL = defaultURL) -> Settings {
        guard let data = try? Data(contentsOf: url) else { return Settings() }
        return decode(data)
    }

    /// garbage, non-object json or an empty phone topic never throws: defaults fill in
    public static func decode(_ data: Data) -> Settings {
        var s = (try? JSONDecoder().decode(Settings.self, from: data)) ?? Settings()
        if s.phoneTopic.trimmingCharacters(in: .whitespaces).isEmpty {
            s.phoneTopic = Settings.randomTopic()
        }
        return s
    }

    public static func encode(_ settings: Settings) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? enc.encode(settings)
    }

    /// false when the file could not be written; errors stay out of the logs (they can name the home folder)
    @discardableResult
    public static func save(_ settings: Settings, to url: URL = defaultURL) -> Bool {
        guard let data = encode(settings) else { return false }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
