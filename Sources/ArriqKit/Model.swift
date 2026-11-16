import Foundation

public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case lamp, speaker, tv
}

public struct DeviceSetting: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var delaySeconds: Int  // 0...120, after the trigger

    public init(enabled: Bool = true, delaySeconds: Int = 0) {
        self.enabled = enabled
        self.delaySeconds = min(max(delaySeconds, 0), 120)
    }

    enum CodingKeys: String, CodingKey { case enabled, delaySeconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true,
            delaySeconds: (try? c.decodeIfPresent(Int.self, forKey: .delaySeconds)) ?? 0
        )
    }
}

/// which lamp arriq drives: a govee light over its lan api, or philips hue through the bridge
public enum LampBrand: String, Codable, CaseIterable, Sendable {
    case govee, hue
}

/// white = colour temperature (warmth), color = a hue at full saturation
public enum LampMode: String, Codable, CaseIterable, Sendable {
    case white, color
}

public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var lamp: DeviceSetting
    public var speaker: DeviceSetting
    public var tv: DeviceSetting
    public var lampBrightness: Int       // 1...100
    public var lampKelvin: Int           // 2000...9000
    public var lampMode: LampMode
    public var lampBrand: LampBrand
    public var hueBridgeIP: String?      // local address of the hue bridge; the key itself lives in the keychain
    public var hueTarget: String?        // "group:<id>" (a room or zone) or "light:<id>"
    public var lampHue: Int              // 0...359 degrees, used in color mode
    public var lampIP: String?           // cached after a lan scan
    public var speakerAddress: String    // classic bluetooth address, upper-case, colon separated
    public var smartThingsDeviceID: String?
    public var phoneTopic: String        // secret ntfy.sh topic the phone posts to
    public var homeGatewayMAC: String?   // lower-case, colon separated, zero padded
    public var cooldownMinutes: Int      // 5...240
    public var pairWindowMinutes: Int    // 1...60
    public var gadgetEnabled: Bool
    public var gadgetFloats: Bool
    public var gadgetOrigin: [Double]?   // [x, y]
    public var gadgetAfterQuit: Bool     // the gadget stays on the desktop after arriq quits
    public var launchAtLogin: Bool
    public var musicEnabled: Bool
    public var spotifyLink: String       // pasted spotify link, trimmed
    public var musicVolume: Int          // 0...100
    public var musicShuffle: Bool
    public var tvSceneEnabled: Bool
    public var tvSceneLink: String       // pasted youtube link
    public var tvIP: String?             // optional, enables the dial launch

    public init(
        enabled: Bool = true,
        lamp: DeviceSetting = DeviceSetting(enabled: true, delaySeconds: 0),
        speaker: DeviceSetting = DeviceSetting(enabled: true, delaySeconds: 2),
        tv: DeviceSetting = DeviceSetting(enabled: true, delaySeconds: 4),
        lampBrightness: Int = 60,
        lampKelvin: Int = 2700,
        lampMode: LampMode = .white,
        lampBrand: LampBrand = .govee,
        hueBridgeIP: String? = nil,
        hueTarget: String? = nil,
        lampHue: Int = 25,
        lampIP: String? = nil,
        speakerAddress: String = "",
        smartThingsDeviceID: String? = nil,
        phoneTopic: String = Settings.randomTopic(),
        homeGatewayMAC: String? = nil,
        cooldownMinutes: Int = 30,
        pairWindowMinutes: Int = 15,
        gadgetEnabled: Bool = true,
        gadgetFloats: Bool = false,
        gadgetOrigin: [Double]? = nil,
        gadgetAfterQuit: Bool = true,
        launchAtLogin: Bool = false,
        musicEnabled: Bool = false,
        spotifyLink: String = "",
        musicVolume: Int = 40,
        musicShuffle: Bool = true,
        tvSceneEnabled: Bool = true,
        tvSceneLink: String = "",
        tvIP: String? = nil
    ) {
        self.enabled = enabled
        self.lamp = lamp
        self.speaker = speaker
        self.tv = tv
        self.lampBrightness = min(max(lampBrightness, 1), 100)
        self.lampKelvin = min(max(lampKelvin, 2000), 9000)
        self.lampMode = lampMode
        self.lampBrand = lampBrand
        self.hueBridgeIP = hueBridgeIP.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.hueTarget = hueTarget
        self.lampHue = ((lampHue % 360) + 360) % 360
        self.lampIP = lampIP
        self.speakerAddress = speakerAddress
        self.smartThingsDeviceID = smartThingsDeviceID
        self.phoneTopic = phoneTopic
        self.homeGatewayMAC = homeGatewayMAC
        self.cooldownMinutes = min(max(cooldownMinutes, 5), 240)
        self.pairWindowMinutes = min(max(pairWindowMinutes, 1), 60)
        self.gadgetEnabled = gadgetEnabled
        self.gadgetFloats = gadgetFloats
        self.gadgetOrigin = gadgetOrigin
        self.gadgetAfterQuit = gadgetAfterQuit
        self.launchAtLogin = launchAtLogin
        self.musicEnabled = musicEnabled
        self.spotifyLink = spotifyLink.trimmingCharacters(in: .whitespacesAndNewlines)
        self.musicVolume = min(max(musicVolume, 0), 100)
        self.musicShuffle = musicShuffle
        self.tvSceneEnabled = tvSceneEnabled
        self.tvSceneLink = tvSceneLink.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tvIP = tvIP
    }

    enum CodingKeys: String, CodingKey {
        case enabled, lamp, speaker, tv, lampBrightness, lampKelvin, lampMode, lampHue, lampBrand, hueBridgeIP, hueTarget, lampIP, speakerAddress
        case smartThingsDeviceID, phoneTopic, homeGatewayMAC, cooldownMinutes, pairWindowMinutes
        case gadgetEnabled, gadgetFloats, gadgetOrigin, gadgetAfterQuit, launchAtLogin
        case musicEnabled, spotifyLink, musicVolume, musicShuffle, tvSceneEnabled, tvSceneLink, tvIP
    }

    /// tolerant: missing, mistyped or unknown keys fall back to defaults; never throws on a keyed container.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func get<T: Decodable>(_ k: CodingKeys, _ fallback: T) -> T {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil) ?? fallback
        }
        func opt<T: Decodable>(_ k: CodingKeys) -> T? {
            ((try? c.decodeIfPresent(T.self, forKey: k)) ?? nil)
        }
        self.init(
            enabled: get(.enabled, d.enabled),
            lamp: get(.lamp, d.lamp),
            speaker: get(.speaker, d.speaker),
            tv: get(.tv, d.tv),
            lampBrightness: get(.lampBrightness, d.lampBrightness),
            lampKelvin: get(.lampKelvin, d.lampKelvin),
            lampMode: get(.lampMode, d.lampMode),
            lampBrand: get(.lampBrand, d.lampBrand),
            hueBridgeIP: opt(.hueBridgeIP),
            hueTarget: opt(.hueTarget),
            lampHue: get(.lampHue, d.lampHue),
            lampIP: opt(.lampIP),
            speakerAddress: get(.speakerAddress, d.speakerAddress),
            smartThingsDeviceID: opt(.smartThingsDeviceID),
            phoneTopic: get(.phoneTopic, d.phoneTopic),
            homeGatewayMAC: opt(.homeGatewayMAC),
            cooldownMinutes: get(.cooldownMinutes, d.cooldownMinutes),
            pairWindowMinutes: get(.pairWindowMinutes, d.pairWindowMinutes),
            gadgetEnabled: get(.gadgetEnabled, d.gadgetEnabled),
            gadgetFloats: get(.gadgetFloats, d.gadgetFloats),
            gadgetOrigin: opt(.gadgetOrigin),
            gadgetAfterQuit: get(.gadgetAfterQuit, d.gadgetAfterQuit),
            launchAtLogin: get(.launchAtLogin, d.launchAtLogin),
            musicEnabled: get(.musicEnabled, d.musicEnabled),
            spotifyLink: get(.spotifyLink, d.spotifyLink),
            musicVolume: get(.musicVolume, d.musicVolume),
            musicShuffle: get(.musicShuffle, d.musicShuffle),
            tvSceneEnabled: get(.tvSceneEnabled, d.tvSceneEnabled),
            tvSceneLink: get(.tvSceneLink, d.tvSceneLink),
            tvIP: opt(.tvIP)
        )
    }

    public func setting(for kind: DeviceKind) -> DeviceSetting {
        switch kind {
        case .lamp: return lamp
        case .speaker: return speaker
        case .tv: return tv
        }
    }

    /// 20 random hex chars; the topic is the only secret between phone and mac.
    public static func randomTopic() -> String {
        "arriq-" + (0..<10).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

// MARK: presence (pure logic lives in Presence.swift, kit agent)

public enum PresenceEvent: Equatable, Sendable {
    case phoneArrived
    case phoneLeft
    case macHome(Bool)
    case tick  // time passes; expires the pair window
}

public struct PresenceState: Equatable, Sendable {
    public var phoneHome: Bool?      // nil = never heard from the phone
    public var macHome: Bool
    public var armedUntil: Date?     // phone is back, waiting for the mac to come home too
    public var lastTrigger: Date?

    public init(phoneHome: Bool? = nil, macHome: Bool = false, armedUntil: Date? = nil, lastTrigger: Date? = nil) {
        self.phoneHome = phoneHome
        self.macHome = macHome
        self.armedUntil = armedUntil
        self.lastTrigger = lastTrigger
    }
}

public struct PresenceConfig: Equatable, Sendable {
    public var cooldown: TimeInterval
    public var pairWindow: TimeInterval
    public init(cooldown: TimeInterval = 1800, pairWindow: TimeInterval = 900) {
        self.cooldown = cooldown
        self.pairWindow = pairWindow
    }
}

// MARK: engine api (implemented by the kit agent in ArriqEngine.swift; ui agent codes against this)

public enum DeviceStatus: Equatable, Sendable {
    case notSetUp(String)   // e.g. "add a smartthings token"
    case ready
    case working
    case done
    case failed(String)     // short lower-case reason
}

public struct LogLine: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let time: Date
    public let text: String  // lower-case
    public init(id: UUID = UUID(), time: Date = Date(), text: String) {
        self.id = id; self.time = time; self.text = text
    }
}

public struct SmartThingsDevice: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct EngineSnapshot: Equatable, Sendable {
    public var phoneHome: Bool?
    public var macHome: Bool
    public var armedUntil: Date?
    public var listening: Bool          // ntfy stream is live
    public var lastPhoneSignal: Date?
    public var lastTrigger: Date?
    public var gatewayMAC: String?      // what the mac sees right now
    public var lamp: DeviceStatus
    public var speaker: DeviceStatus
    public var tv: DeviceStatus
    public var smartThingsTokenSet: Bool
    public var log: [LogLine]           // newest last, max 200
    /// what arriq last switched each device to; missing = unknown (nothing sent since launch)
    public var power: [DeviceKind: Bool] = [:]
    public var hueKeySet = false

    public static let initial = EngineSnapshot(
        phoneHome: nil, macHome: false, armedUntil: nil, listening: false, lastPhoneSignal: nil,
        lastTrigger: nil, gatewayMAC: nil, lamp: .ready, speaker: .ready, tv: .notSetUp("add a smartthings token"),
        smartThingsTokenSet: false, log: []
    )
}
