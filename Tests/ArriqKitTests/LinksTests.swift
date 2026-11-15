import Foundation
import Testing
@testable import ArriqKit

private let sid = "37i9dQZF1DXcBWIGoYBM5M"

@Test func spotifyLinks() {
    let cases: [(String, String?)] = [
        ("https://open.spotify.com/playlist/\(sid)?si=abc123", "spotify:playlist:\(sid)"),
        ("https://open.spotify.com/intl-de/album/\(sid)", "spotify:album:\(sid)"),
        ("  http://open.spotify.com/track/\(sid)#frag  ", "spotify:track:\(sid)"),
        ("spotify:playlist:\(sid)", "spotify:playlist:\(sid)"),
        ("spotify:album:\(sid)", "spotify:album:\(sid)"),
        ("spotify:track:\(sid)", "spotify:track:\(sid)"),
        ("https://open.spotify.com/artist/\(sid)", nil),
        ("spotify:artist:\(sid)", nil),
        ("https://example.com/playlist/\(sid)", nil),
        ("https://open.spotify.com/playlist/short", nil),
        ("", nil),
    ]
    for (raw, want) in cases { #expect(SpotifyLink.uri(from: raw) == want) }
}

@Test func spotifyKinds() {
    #expect(SpotifyLink.kind(ofURI: "spotify:playlist:\(sid)") == "playlist")
    #expect(SpotifyLink.kind(ofURI: "spotify:album:\(sid)") == "album")
    #expect(SpotifyLink.kind(ofURI: "spotify:track:\(sid)") == "track")
    #expect(SpotifyLink.kind(ofURI: "nope") == nil)
}

@Test func youtubeLinks() {
    let id = "dQw4w9WgXcQ"
    let cases: [(String, String?)] = [
        (id, id),
        ("https://www.youtube.com/watch?v=\(id)", id),
        ("https://www.youtube.com/watch?list=x&v=\(id)&t=5s", id),
        ("https://youtu.be/\(id)?si=zzz", id),
        ("https://www.youtube.com/live/\(id)?feature=share", id),
        ("https://www.youtube.com/embed/\(id)", id),
        ("https://www.youtube.com/shorts/\(id)", id),
        ("https://example.com/watch?v=\(id)", nil),
        ("https://www.youtube.com/watch?v=short", nil),
        ("not a link", nil),
        ("", nil),
    ]
    for (raw, want) in cases { #expect(YouTubeLink.videoID(from: raw) == want) }
}
