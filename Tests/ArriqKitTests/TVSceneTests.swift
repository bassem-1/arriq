import Foundation
import Testing
@testable import ArriqKit

@Test func dialRequestShape() throws {
    let r = try #require(TVScene.dialRequest(ip: "192.168.1.20", videoID: "dQw4w9WgXcQ"))
    #expect(r.url?.absoluteString == "http://192.168.1.20:8080/ws/apps/YouTube")
    #expect(r.httpMethod == "POST")
    #expect(r.value(forHTTPHeaderField: "Content-Type") == "text/plain")
    #expect(r.httpBody == Data("v=dQw4w9WgXcQ".utf8))
    #expect(r.timeoutInterval == 5)
    #expect(TVScene.dialRequest(ip: "", videoID: "x") == nil)
}

@Test func sceneConstants() {
    #expect(TVScene.youtubeAppID == "111299001912")
    #expect(TVScene.backoff == [6, 6, 8, 10])
}

@Test func dryRunTVScene() async {
    var s = Settings(smartThingsDeviceID: "d1", tvSceneEnabled: true, tvSceneLink: "https://youtu.be/dQw4w9WgXcQ")
    let on = await TVDriver.run(settings: s, dryRun: true)
    #expect(on.text == "dry run: tv on · scene")
    s.tvSceneLink = ""
    let off = await TVDriver.run(settings: s, dryRun: true)
    #expect(off.text == "dry run: tv on · d1")
}
