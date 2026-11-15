import Foundation
import Testing
@testable import ArriqKit

@Test func musicScriptSetsVolumeShuffleAndPlays() {
    let s = MusicDriver.script(uri: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M", volume: 40, shuffle: true)
    #expect(s.contains("set sound volume to 40"))
    #expect(s.contains("set shuffling to true"))
    #expect(s.contains("play track \"spotify:playlist:37i9dQZF1DXcBWIGoYBM5M\""))
    #expect(MusicDriver.script(uri: "u", volume: 150, shuffle: false).contains("set shuffling to false"))
    #expect(MusicDriver.script(uri: "u", volume: 150, shuffle: false).contains("sound volume to 100"))
}

@Test func musicReasons() {
    #expect(MusicDriver.reason(osascriptStderr: "execution error: Not authorized to send Apple events to Spotify. (-1743)")
            == "not allowed to control spotify")
    #expect(MusicDriver.reason(osascriptStderr: "Application isn't running. (-600)") == "spotify did not respond")
    #expect(MusicDriver.reason(osascriptStderr: "") == "spotify did not respond")
}

@Test func uidMatchesBluetoothAddress() {
    #expect(AudioRoute.uidMatches("a1-b2-c3-d4-e5-f6:output", address: "A1:B2:C3:D4:E5:F6"))
    #expect(!AudioRoute.uidMatches("AppleHDAEngineOutput:1B,0,1,2:0", address: "A1:B2:C3:D4:E5:F6"))
    #expect(!AudioRoute.uidMatches("anything", address: ""))
}

@Test func dryRunMusic() async {
    var s = Settings(musicEnabled: true, spotifyLink: "spotify:album:37i9dQZF1DXcBWIGoYBM5M", musicVolume: 55)
    let ok = await MusicDriver.run(settings: s, dryRun: true)
    #expect(ok == DeviceOutcome(ok: true, text: "dry run: music · album · vol 55"))
    s.spotifyLink = "nope"
    let bad = await MusicDriver.run(settings: s, dryRun: true)
    #expect(bad == DeviceOutcome(ok: false, text: "music failed · not a spotify link"))
}
