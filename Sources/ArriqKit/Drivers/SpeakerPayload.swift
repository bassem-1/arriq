import Foundation

/// pure helpers for the ue boom ble wake. byte order is the order the address is printed in.
public enum SpeakerWake {
    public static let shortServiceUUID = "FE61"
    public static let serviceUUID = "000061FE-0000-1000-8000-00805F9B34FB"
    public static let characteristicUUID = "C6D6DC0D-07F5-47EF-9B59-630622B01FD3"

    /// "A1:B2:C3:D4:E5:F6" -> 6 bytes; nil unless six hex octets
    public static func addressBytes(_ address: String) -> [UInt8]? {
        let parts = address.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }
        var out: [UInt8] = []
        for p in parts {
            guard p.count == 2, let b = UInt8(p, radix: 16) else { return nil }
            out.append(b)
        }
        return out
    }

    /// postel: colons, dashes, spaces or nothing between octets, any case -> "A1:B2:C3:D4:E5:F6"; nil otherwise
    public static func normalize(_ raw: String) -> String? {
        let hex = raw.uppercased().filter { !":- \t\n".contains($0) }
        guard hex.count == 12, hex.allSatisfy(\.isHexDigit) else { return nil }
        var octets: [String] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            octets.append(String(hex[i..<j]))
            i = j
        }
        return octets.joined(separator: ":")
    }

    public static let powerOn: UInt8 = 0x01
    public static let powerOff: UInt8 = 0x02

    /// host address bytes followed by the command byte: 0x01 on, 0x02 off
    public static func payload(hostAddress: String, command: UInt8 = powerOn) -> Data? {
        guard let bytes = addressBytes(hostAddress) else { return nil }
        return Data(bytes + [command])
    }

    /// matches on the wake service, or on the speaker's six address bytes inside manufacturer data
    public static func advertisementMatches(serviceUUIDs: [String], manufacturerData: Data?, speaker: [UInt8]) -> Bool {
        let wanted = [shortServiceUUID, serviceUUID]
        if serviceUUIDs.contains(where: { wanted.contains($0.uppercased()) }) { return true }
        guard let md = manufacturerData, speaker.count == 6, md.count >= 6 else { return false }
        let bytes = [UInt8](md)
        return (0...(bytes.count - 6)).contains { i in Array(bytes[i..<(i + 6)]) == speaker }
    }
}
