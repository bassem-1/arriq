import Foundation
import Testing
@testable import ArriqKit

// on demand on, believed power state, lamp colour and live adjust. dry run only.

@MainActor
private func settle(until done: () -> Bool) async {
    for _ in 0..<150 where !done() {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@Test func hueMapsToFullSaturationRGB() {
    #expect(LampColor.rgb(hue: 0) == (255, 0, 0))
    #expect(LampColor.rgb(hue: 120) == (0, 255, 0))
    #expect(LampColor.rgb(hue: 240) == (0, 0, 255))
    #expect(LampColor.rgb(hue: 60) == (255, 255, 0))
    #expect(LampColor.rgb(hue: 360) == (255, 0, 0))   // wraps
    #expect(LampColor.rgb(hue: -120) == (0, 0, 255))  // wraps backwards
}

@Test func hueHasAWord() {
    #expect(LampColor.name(hue: 0) == "red")
    #expect(LampColor.name(hue: 25) == "orange")
    #expect(LampColor.name(hue: 120) == "green")
    #expect(LampColor.name(hue: 220) == "blue")
    #expect(LampColor.name(hue: 350) == "red")
}

private func command(_ data: Data) -> [String: Any]? {
    ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["msg"] as? [String: Any]
}

@Test func shadeFollowsTheLampMode() {
    var s = Settings()
    s.lampMode = .white
    s.lampKelvin = 3000
    let white = command(GoveeCommand.shade(s))?["data"] as? [String: Any]
    #expect(white?["colorTemInKelvin"] as? Int == 3000)

    s.lampMode = .color
    s.lampHue = 240
    let colour = command(GoveeCommand.shade(s))?["data"] as? [String: Any]
    #expect(colour?["colorTemInKelvin"] as? Int == 0)
    let rgb = colour?["color"] as? [String: Int]
    #expect(rgb == ["r": 0, "g": 0, "b": 255])
}

@Test func lampColourSettingsDecodeTolerantly() throws {
    let d = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
    #expect(d.lampMode == .white)
    #expect(d.lampHue == 25)
    let set = try JSONDecoder().decode(Settings.self, from: Data(#"{"lampMode": "color", "lampHue": 400}"#.utf8))
    #expect(set.lampMode == .color)
    #expect(set.lampHue == 40)  // wrapped into 0...359
    let junk = try JSONDecoder().decode(Settings.self, from: Data(#"{"lampMode": "disco", "lampHue": "x"}"#.utf8))
    #expect(junk.lampMode == .white)
    #expect(junk.lampHue == 25)
}

@MainActor
@Test func powerIsUnknownThenFollowsOnAndOff() async {
    let engine = ArriqEngine(dryRun: true)
    engine.apply(Settings())
    #expect(engine.snapshot.power[.lamp] == nil)
    engine.turnOn(.lamp)
    await settle { engine.snapshot.power[.lamp] != nil }
    #expect(engine.snapshot.power[.lamp] == true)
    engine.turnOff(.lamp)
    await settle { engine.snapshot.power[.lamp] == false }
    #expect(engine.snapshot.power[.lamp] == false)
}

@MainActor
@Test func turnOnIgnoresTheOnArrivalSwitch() async {
    let engine = ArriqEngine(dryRun: true)
    var s = Settings()
    s.speaker = DeviceSetting(enabled: false, delaySeconds: 90)  // not used on arrival, long delay
    engine.apply(s)
    engine.turnOn(.speaker)
    await settle { engine.snapshot.power[.speaker] == true }
    #expect(engine.snapshot.log.map(\.text).contains { $0.hasPrefix("dry run: speaker wake") })
}

@MainActor
@Test func turnOnAllSwitchesEveryDeviceNowWithoutDelays() async {
    let engine = ArriqEngine(dryRun: true)
    engine.tokenProbe = { false }
    engine.apply(Settings())  // default delays 0 / 2 / 4 s
    engine.turnOnAll()
    await settle { engine.snapshot.power[.lamp] == true && engine.snapshot.power[.speaker] == true }
    #expect(engine.snapshot.log.first?.text == "all on")
    #expect(engine.snapshot.power[.speaker] == true)  // well before its 2 s arrival delay
}

@MainActor
@Test func liveAdjustOnlyWhileTheLampIsOn() async {
    let engine = ArriqEngine(dryRun: true)
    var s = Settings()
    s.lampMode = .color
    s.lampHue = 220
    s.lampBrightness = 40
    engine.apply(s)
    engine.adjustLamp()  // power unknown: nothing is sent
    try? await Task.sleep(nanoseconds: 100_000_000)
    #expect(engine.adjustStamp == 0)

    engine.turnOn(.lamp)
    await settle { engine.snapshot.power[.lamp] == true }
    engine.adjustLamp()
    #expect(engine.adjustStamp == 1)
    #expect(LampDriver.blockingAdjust(settings: s, dryRun: true).text == "dry run: lamp set · 40 · blue")
}
