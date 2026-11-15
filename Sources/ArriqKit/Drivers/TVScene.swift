import Foundation

/// pure helpers for starting a youtube video on the tv after it is switched on
public enum TVScene {
    static let youtubeAppID = "111299001912"
    /// waits before each attempt while the tv boots
    static let backoff: [TimeInterval] = [6, 6, 8, 10]

    /// dial launch: POST http://<ip>:8080/ws/apps/YouTube with body v=<id>
    static func dialRequest(ip: String, videoID: String) -> URLRequest? {
        let host = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let url = URL(string: "http://\(host):8080/ws/apps/YouTube"),
              url.host != nil else { return nil }
        var r = URLRequest(url: url)
        r.httpMethod = "POST"
        r.timeoutInterval = 5
        r.httpBody = Data("v=\(videoID)".utf8)
        r.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        return r
    }
}
