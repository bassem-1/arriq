import Foundation

/// a room, zone or single light on the hue bridge, as arriq can target it
public struct HueTarget: Identifiable, Equatable, Sendable {
    public let id: String      // "group:<id>" or "light:<id>"
    public let label: String   // lower-case
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public enum HuePair: Equatable, Sendable {
    case key(String)
    case pressButton
    case failed(String)
}

/// philips hue bridge, local api (clip v1 over https). request builders and parsers are pure and tested.
/// the key (the bridge's "username") is a secret: it is only ever passed in, never stored or logged here.
public enum HueAPI {
    public static let devicetype = "arriq#mac"

    static func url(_ ip: String, _ path: String) -> URL? {
        guard NetParse.isIPv4(ip) else { return nil }
        return URL(string: "https://\(ip)\(path)")
    }

    static func request(_ url: URL, method: String, body: [String: Any]? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 5
        if let body, let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) {
            r.httpBody = data
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    // MARK: pairing

    public static func pairRequest(ip: String) -> URLRequest? {
        url(ip, "/api").map { request($0, method: "POST", body: ["devicetype": devicetype]) }
    }

    /// [{"success":{"username":"…"}}] or [{"error":{"type":101,…}}]
    public static func parsePair(_ data: Data) -> HuePair {
        guard let first = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first else {
            return .failed("not a hue bridge")
        }
        if let key = (first["success"] as? [String: Any])?["username"] as? String, !key.isEmpty { return .key(key) }
        if let err = first["error"] as? [String: Any] {
            if err["type"] as? Int == 101 { return .pressButton }
            return .failed(reason(err))
        }
        return .failed("not a hue bridge")
    }

    /// the unauthenticated config: proves an address is a hue bridge and gives its name
    public static func configRequest(ip: String) -> URLRequest? {
        url(ip, "/api/config").map { request($0, method: "GET") }
    }

    public static func parseBridgeName(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["bridgeid"] != nil || (obj["modelid"] as? String)?.hasPrefix("BSB") == true else { return nil }
        return ((obj["name"] as? String) ?? "hue bridge").lowercased()
    }

    // MARK: rooms and lights

    public static func groupsRequest(ip: String, key: String) -> URLRequest? {
        url(ip, "/api/\(key)/groups").map { request($0, method: "GET") }
    }

    public static func lightsRequest(ip: String, key: String) -> URLRequest? {
        url(ip, "/api/\(key)/lights").map { request($0, method: "GET") }
    }

    /// rooms and zones only (not entertainment areas), sorted by name
    public static func parseGroups(_ data: Data) -> [HueTarget] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return obj.compactMap { id, g in
            guard let type = g["type"] as? String, type == "Room" || type == "Zone",
                  let name = g["name"] as? String else { return nil }
            return HueTarget(id: "group:\(id)", label: name.lowercased())
        }
        .sorted { $0.label < $1.label }
    }

    public static func parseLights(_ data: Data) -> [HueTarget] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        return obj.compactMap { id, l in
            (l["name"] as? String).map { HueTarget(id: "light:\(id)", label: $0.lowercased()) }
        }
        .sorted { $0.label < $1.label }
    }

    // MARK: state

    /// 1...100 % -> 1...254
    public static func bri(_ percent: Int) -> Int { min(max(Int((Double(percent) * 254 / 100).rounded()), 1), 254) }

    /// kelvin -> mired, inside the range hue white ambiance accepts
    public static func mired(_ kelvin: Int) -> Int { min(max(Int((1_000_000 / Double(max(kelvin, 1))).rounded()), 153), 500) }

    /// 0...359 degrees -> 0...65535
    public static func hueValue(_ degrees: Int) -> Int { (((degrees % 360) + 360) % 360) * 65535 / 360 }

    /// on = true / false switches; nil only changes brightness and colour (live adjust)
    public static func stateBody(_ s: Settings, on: Bool?) -> [String: Any] {
        if on == false { return ["on": false] }
        var body: [String: Any] = ["bri": bri(s.lampBrightness)]
        if on == true { body["on"] = true }
        switch s.lampMode {
        case .white: body["ct"] = mired(s.lampKelvin)
        case .color:
            body["hue"] = hueValue(s.lampHue)
            body["sat"] = 254
        }
        return body
    }

    public static func stateRequest(ip: String, key: String, target: String, body: [String: Any]) -> URLRequest? {
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        // hue ids are short and alphanumeric; anything else is refused, never escaped into a path
        guard parts.count == 2, !parts[1].isEmpty, parts[1].count <= 64,
              parts[1].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let id = parts[1]
        let path: String
        switch parts[0] {
        case "group": path = "/api/\(key)/groups/\(id)/action"
        case "light": path = "/api/\(key)/lights/\(id)/state"
        default: return nil
        }
        return url(ip, path).map { request($0, method: "PUT", body: body) }
    }

    /// nil when every item succeeded, else a short lower-case reason
    public static func parseResult(_ data: Data) -> String? {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return "bridge did not answer"
        }
        if let err = items.compactMap({ $0["error"] as? [String: Any] }).first { return reason(err) }
        return nil
    }

    static func reason(_ err: [String: Any]) -> String {
        switch err["type"] as? Int {
        case 1: return "key rejected · pair again"
        case 3: return "light not found · pick again"
        case 101: return "press the bridge button first"
        case 201: return "light is off at the switch"
        default: return ((err["description"] as? String) ?? "bridge error").lowercased()
        }
    }
}

/// the bridge serves https with its own certificate. this session trusts that certificate for the bridge
/// address it was made for, and nothing else, so the key never travels in plain text.
final class HueSession: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let host: String
    private(set) lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)

    init(host: String) { self.host = host }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              space.host == host, let trust = space.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func data(_ request: URLRequest) async -> Data? {
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return nil }
        return data
    }
}
