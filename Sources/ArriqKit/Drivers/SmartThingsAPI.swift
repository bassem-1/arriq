import Foundation

/// smartthings cloud rest calls. request builders and parsers are pure and tested.
public enum SmartThingsAPI {
    static let devicesURL = "https://api.smartthings.com/v1/devices"

    public static func devicesRequest(token: String) -> URLRequest? {
        guard let url = URL(string: devicesURL) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "GET"
        r.timeoutInterval = 10
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    public static func commandRequest(deviceID: String, token: String) -> URLRequest? {
        commandRequest(deviceID: deviceID, token: token, capability: "switch", command: "on")
    }

    public static func commandRequest(deviceID: String, token: String, capability: String, command: String,
                                      arguments: [Any] = []) -> URLRequest? {
        guard let escaped = deviceID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(devicesURL)/\(escaped)/commands") else { return nil }
        var item: [String: Any] = ["component": "main", "capability": capability, "command": command]
        if !arguments.isEmpty { item["arguments"] = arguments }
        let body: [String: Any] = ["commands": [item]]
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 10
        r.httpBody = data
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }

    static func reason(forStatus code: Int) -> String {
        switch code {
        case 401: return "token expired"
        case 403: return "token lacks device control"
        default: return "http \(code)"
        }
    }

    /// extra log line for a failed command
    static func hint(forReason reason: String) -> String? {
        reason == "token expired" ? "new smartthings tokens last 24h" : nil
    }

    /// items[].deviceId with label (or name) lower-cased; entries without an id are skipped
    public static func parseDevices(_ data: Data) -> [SmartThingsDevice] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["deviceId"] as? String, !id.isEmpty else { return nil }
            let named = (item["label"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (item["name"] as? String)
                ?? id
            return SmartThingsDevice(id: id, label: named.lowercased())
        }
    }

    public static func listDevices(token: String, session: URLSession = .shared) async -> [SmartThingsDevice] {
        guard let req = devicesRequest(token: token),
              let result = try? await session.data(for: req),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return parseDevices(result.0)
    }

    /// nil on success, else a short lower-case reason
    public static func sendOn(deviceID: String, token: String, session: URLSession = .shared) async -> String? {
        await send(deviceID: deviceID, token: token, capability: "switch", command: "on", session: session)
    }

    /// nil on success, else a short lower-case reason
    public static func send(deviceID: String, token: String, capability: String, command: String,
                            arguments: [Any] = [], session: URLSession = .shared) async -> String? {
        guard let req = commandRequest(deviceID: deviceID, token: token, capability: capability,
                                       command: command, arguments: arguments) else { return "bad request" }
        do {
            let (_, response) = try await session.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (200..<300).contains(code) ? nil : reason(forStatus: code)
        } catch let error as URLError where error.code == .timedOut {
            return "timed out"
        } catch {
            return "network error"
        }
    }
}
