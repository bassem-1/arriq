import Foundation

/// json builders for the govee lan api (udp). pure, tested.
public enum GoveeCommand {
    public static let multicastIP = "239.255.255.250"
    public static let scanPort: UInt16 = 4001
    public static let replyPort: UInt16 = 4002
    public static let devicePort: UInt16 = 4003

    public static func scan() -> Data { envelope(cmd: "scan", data: ["account_topic": "reserve"]) }
    public static func devStatus() -> Data { envelope(cmd: "devStatus", data: [:]) }
    public static func turn(on: Bool) -> Data { envelope(cmd: "turn", data: ["value": on ? 1 : 0]) }
    public static func brightness(_ percent: Int) -> Data {
        envelope(cmd: "brightness", data: ["value": clamp(percent, 1, 100)])
    }
    /// warm white: colour channels zero, colour temperature in kelvin
    public static func warmWhite(kelvin: Int) -> Data {
        envelope(cmd: "colorwc", data: [
            "color": ["r": 0, "g": 0, "b": 0],
            "colorTemInKelvin": clamp(kelvin, 2000, 9000),
        ])
    }

    /// colour: rgb channels, colour temperature zero
    public static func color(r: Int, g: Int, b: Int) -> Data {
        envelope(cmd: "colorwc", data: [
            "color": ["r": clamp(r, 0, 255), "g": clamp(g, 0, 255), "b": clamp(b, 0, 255)],
            "colorTemInKelvin": 0,
        ])
    }

    /// the colour command for the lamp's current mode
    public static func shade(_ s: Settings) -> Data {
        switch s.lampMode {
        case .white: return warmWhite(kelvin: s.lampKelvin)
        case .color:
            let c = LampColor.rgb(hue: s.lampHue)
            return color(r: c.r, g: c.g, b: c.b)
        }
    }

    /// msg.data.ip from a scan reply
    public static func scanIP(from reply: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let msg = obj["msg"] as? [String: Any],
              let data = msg["data"] as? [String: Any],
              let ip = data["ip"] as? String,
              NetParse.isIPv4(ip) else { return nil }
        return ip
    }

    static func envelope(cmd: String, data: [String: Any]) -> Data {
        let inner: [String: Any] = ["cmd": cmd, "data": data]
        let obj: [String: Any] = ["msg": inner]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
    }

    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(max(v, lo), hi) }
}
