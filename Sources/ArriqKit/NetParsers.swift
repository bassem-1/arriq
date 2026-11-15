import Foundation

/// pure parsers for `route -n get default` and `arp -n <ip>` output.
public enum NetParse {
    /// the "gateway: a.b.c.d" line of `route -n get default`
    public static func gateway(fromRoute output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "gateway", isIPv4(parts[1]) {
                return parts[1]
            }
        }
        return nil
    }

    /// the mac after "at" in `arp -n <ip>`; nil for "(incomplete)" or anything unparsable
    public static func mac(fromARP output: String) -> String? {
        let tokens = output.split(whereSeparator: { $0.isWhitespace })
        guard let i = tokens.firstIndex(of: "at") else { return nil }
        let next = tokens.index(after: i)
        guard next < tokens.endIndex else { return nil }
        return normalizeMAC(String(tokens[next]))
    }

    /// "0:1d:2:3e:4f:5" -> "00:1d:02:3e:4f:05"; nil unless six hex octets
    public static func normalizeMAC(_ raw: String) -> String? {
        let parts = raw.trimmingCharacters(in: .whitespaces).lowercased()
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6 else { return nil }
        var out: [String] = []
        for p in parts {
            guard (1...2).contains(p.count), p.allSatisfy(\.isHexDigit) else { return nil }
            out.append(p.count == 1 ? "0" + p : String(p))
        }
        return out.joined(separator: ":")
    }

    public static func isIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { p in
            p.count >= 1 && p.count <= 3 && p.allSatisfy({ $0.isASCII && $0.isNumber }) && (Int(p) ?? 256) <= 255
        }
    }

    /// the mac to save as home on first sight: only when nothing is saved yet and the gateway mac is readable
    public static func homeToAdopt(saved: String?, current: String?) -> String? {
        guard saved == nil else { return nil }
        return current.flatMap(normalizeMAC)
    }

    /// true when both ips are valid and agree on every bit covered by the netmask
    public static func sameSubnet(_ a: String, _ b: String, mask: String) -> Bool {
        guard let x = ipv4Bits(a), let y = ipv4Bits(b), let m = ipv4Bits(mask) else { return false }
        return (x & m) == (y & m)
    }

    static func ipv4Bits(_ s: String) -> UInt32? {
        guard isIPv4(s) else { return nil }
        var v: UInt32 = 0
        for part in s.split(separator: ".") {
            guard let octet = UInt32(part), octet <= 255 else { return nil }
            v = (v << 8) | octet
        }
        return v
    }

    /// true only when both macs are known and equal after normalizing
    public static func isHome(gatewayMAC: String?, homeMAC: String?) -> Bool {
        guard let g = gatewayMAC.flatMap(normalizeMAC), let h = homeMAC.flatMap(normalizeMAC) else { return false }
        return g == h
    }
}
