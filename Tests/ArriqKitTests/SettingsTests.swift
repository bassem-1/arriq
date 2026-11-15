import Foundation
import Testing
@testable import ArriqKit

@Test func defaultsMatchTheSpec() {
    let s = Settings()
    #expect(s.enabled)
    #expect(s.lamp.delaySeconds == 0)
    #expect(s.speaker.delaySeconds == 2)
    #expect(s.tv.delaySeconds == 4)
    #expect(s.lampBrightness == 60)
    #expect(s.lampKelvin == 2700)
    #expect(s.cooldownMinutes == 30)
    #expect(s.pairWindowMinutes == 15)
    #expect(s.speakerAddress == "")  // no personal default in the code
    #expect(s.phoneTopic.hasPrefix("arriq-"))
    #expect(s.phoneTopic.count == 26)
}

@Test func roundTripKeepsEverything() throws {
    var s = Settings(lampIP: "10.10.1.5", smartThingsDeviceID: "abc-123", homeGatewayMAC: "00:1d:02:3e:4f:05",
                     gadgetOrigin: [10, 20])
    s.enabled = false
    s.tv.delaySeconds = 7
    let data = try #require(SettingsStore.encode(s))
    #expect(SettingsStore.decode(data) == s)
}

@Test func emptyObjectGivesDefaults() {
    let s = SettingsStore.decode(Data("{}".utf8))
    #expect(s.enabled)
    #expect(s.lamp == DeviceSetting(enabled: true, delaySeconds: 0))
    #expect(s.lampBrightness == 60)
    #expect(!s.phoneTopic.isEmpty)
}

@Test func garbageGivesDefaults() {
    for raw in ["nope", "[1,2]", "null", "", "{\"enabled\":"] {
        let s = SettingsStore.decode(Data(raw.utf8))
        #expect(s.enabled)
        #expect(s.lampKelvin == 2700)
    }
}

@Test func unknownKeysAreIgnored() {
    let s = SettingsStore.decode(Data(#"{"enabled": false, "bogus": [1,2,3], "lamp": {"enabled": true, "x": 1}}"#.utf8))
    #expect(!s.enabled)
    #expect(s.lamp.enabled)
}

@Test func wrongTypesFallBackPerKey() {
    let s = SettingsStore.decode(Data(#"{"enabled": "yes", "lampBrightness": "lots", "lamp": 3, "lampIP": 5, "cooldownMinutes": true}"#.utf8))
    #expect(s.enabled)
    #expect(s.lampBrightness == 60)
    #expect(s.lamp == Settings().lamp)
    #expect(s.lampIP == nil)
    #expect(s.cooldownMinutes == 30)
}

@Test func valuesAreClamped() {
    let s = SettingsStore.decode(Data(#"""
    {"lampBrightness": 500, "lampKelvin": 100, "cooldownMinutes": 1, "pairWindowMinutes": 999,
     "lamp": {"delaySeconds": 900}, "tv": {"delaySeconds": -5}}
    """#.utf8))
    #expect(s.lampBrightness == 100)
    #expect(s.lampKelvin == 2000)
    #expect(s.cooldownMinutes == 5)
    #expect(s.pairWindowMinutes == 60)
    #expect(s.lamp.delaySeconds == 120)
    #expect(s.tv.delaySeconds == 0)
}

@Test func emptyTopicIsReplaced() {
    let s = SettingsStore.decode(Data(#"{"phoneTopic": "   "}"#.utf8))
    #expect(s.phoneTopic.hasPrefix("arriq-"))
}

@Test func saveThenLoadFromFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("settings.json")
    var s = Settings()
    s.lampKelvin = 4000
    #expect(SettingsStore.save(s, to: url))
    #expect(SettingsStore.load(from: url) == s)
}

@Test func missingFileGivesDefaults() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("arriq-missing-\(UUID().uuidString).json")
    #expect(SettingsStore.load(from: url).enabled)
}

@Test func musicAndSceneDefaults() {
    let s = Settings()
    #expect(!s.musicEnabled)
    #expect(s.spotifyLink == "")
    #expect(s.musicVolume == 40)
    #expect(s.musicShuffle)
    #expect(s.tvSceneEnabled)
    #expect(s.tvSceneLink == "")
    #expect(s.tvIP == nil)
}

@Test func musicAndSceneRoundTrip() throws {
    let s = Settings(musicEnabled: true, spotifyLink: " spotify:track:4uLU6hMCjMI75M1A2tKUQC ", musicVolume: 65,
                     musicShuffle: false, tvSceneEnabled: false, tvSceneLink: "https://youtu.be/dQw4w9WgXcQ",
                     tvIP: "192.168.1.20")
    #expect(s.spotifyLink == "spotify:track:4uLU6hMCjMI75M1A2tKUQC")
    let data = try #require(SettingsStore.encode(s))
    #expect(SettingsStore.decode(data) == s)
}

@Test func emptyObjectGivesMusicDefaults() {
    let s = SettingsStore.decode(Data("{}".utf8))
    #expect(!s.musicEnabled)
    #expect(s.musicVolume == 40)
    #expect(s.tvSceneEnabled)
    #expect(s.tvIP == nil)
}

@Test func musicVolumeIsClampedAndTolerant() {
    #expect(SettingsStore.decode(Data(#"{"musicVolume":150}"#.utf8)).musicVolume == 100)
    #expect(SettingsStore.decode(Data(#"{"musicVolume":-5}"#.utf8)).musicVolume == 0)
    #expect(SettingsStore.decode(Data(#"{"musicVolume":"loud"}"#.utf8)).musicVolume == 40)
}
