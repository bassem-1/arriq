import Foundation

/// parses pasted spotify links into a canonical uri. pure and tested.
public enum SpotifyLink {
    static let kinds = ["playlist", "album", "track"]

    private static func isID(_ s: Substring) -> Bool {
        s.count == 22 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// `spotify:<kind>:<id>` or an open.spotify.com link; nil for anything else (artist links included)
    public static func uri(from raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.lowercased().hasPrefix("spotify:") {
            let parts = t.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].lowercased() == "spotify",
                  kinds.contains(String(parts[1]).lowercased()), isID(parts[2]) else { return nil }
            return "spotify:\(parts[1].lowercased()):\(parts[2])"
        }
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.lowercased() == "open.spotify.com" else { return nil }
        var segs = url.path.split(separator: "/").map(String.init)
        if let first = segs.first, first.hasPrefix("intl-") { segs.removeFirst() }
        guard segs.count >= 2, kinds.contains(segs[0].lowercased()), isID(Substring(segs[1])) else { return nil }
        return "spotify:\(segs[0].lowercased()):\(segs[1])"
    }

    /// playlist, album or track
    public static func kind(ofURI uri: String) -> String? {
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify", kinds.contains(String(parts[1])) else { return nil }
        return String(parts[1])
    }
}

/// extracts an 11 character video id from a pasted youtube link. pure and tested.
public enum YouTubeLink {
    private static func isID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    public static func videoID(from raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isID(t) { return t }
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = url.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let segs = url.path.split(separator: "/").map(String.init)
        if host == "youtu.be" {
            if let id = segs.first, isID(id) { return id }
            return nil
        }
        guard host == "youtube.com" || host == "m.youtube.com" || host == "music.youtube.com" else { return nil }
        if segs.first == "watch" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let v = items.first(where: { $0.name == "v" })?.value, isID(v) { return v }
            return nil
        }
        if segs.count >= 2, ["live", "embed", "shorts"].contains(segs[0]), isID(segs[1]) { return segs[1] }
        return nil
    }
}
