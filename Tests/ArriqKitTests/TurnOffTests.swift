import Foundation
import Testing
@testable import ArriqKit

// on demand off, dry run only: logs, resting states, and an off cancelling a pending arrival run.

@MainActor
private func settle(_ engine: ArriqEngine, until done: () -> Bool) async {
    for _ in 0..<150 where !done() {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
}

@Test func offPayloadEndsInTheOffByte() {
    let on = SpeakerWake.payload(hostAddress: "00:11:22:33:44:55")
    let off = SpeakerWake.payload(hostAddress: "00:11:22:33:44:55", command: SpeakerWake.powerOff)
    #expect(on.map([UInt8].init) == [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x01])
    #expect(off.map([UInt8].init) == [0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x02])
}

@Test func lampOffIsOneTurnCommand() throws {
    let obj = try JSONSerialization.jsonObject(with: GoveeCommand.turn(on: false)) as? [String: Any]
    let msg = obj?["msg"] as? [String: Any]
    #expect(msg?["cmd"] as? String == "turn")
    #expect((msg?["data"] as? [String: Any])?["value"] as? Int == 0)
}

@Test func tvOffIsASwitchOffCommand() throws {
    let r = try #require(SmartThingsAPI.commandRequest(deviceID: "d", token: "t", capability: "switch", command: "off"))
    let body = try #require(r.httpBody)
    let obj = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let cmd = (obj?["commands"] as? [[String: Any]])?.first
    #expect(cmd?["capability"] as? String == "switch")
    #expect(cmd?["command"] as? String == "off")
}

@MainActor
@Test func turnOffLampLogsAndReturnsToReady() async {
    let engine = ArriqEngine(dryRun: true)
    engine.apply(Settings())
    engine.turnOff(.lamp)
    #expect(engine.snapshot.lamp == .working)
    await settle(engine) { engine.snapshot.lamp != .working }
    #expect(engine.snapshot.lamp == .ready)
    #expect(engine.snapshot.log.map(\.text).contains("dry run: lamp off · scan"))
}

@MainActor
@Test func turnOffAllCoversEveryDeviceAndSkipsAnUnsetTV() async {
    let engine = ArriqEngine(dryRun: true)
    engine.tokenProbe = { false }
    engine.apply(Settings())
    engine.turnOffAll()
    await settle(engine) { engine.snapshot.lamp != .working && engine.snapshot.speaker != .working }
    let log = engine.snapshot.log.map(\.text)
    #expect(log.first == "all off")
    #expect(log.contains("dry run: lamp off · scan"))
    #expect(log.contains { $0.hasPrefix("dry run: speaker off") })
    #expect(log.contains("tv off skipped · add a smartthings token"))
    #expect(engine.snapshot.tv == .notSetUp("add a smartthings token"))
}

@MainActor
@Test func speakerOffAlsoPausesTheMusicWhenMusicIsOn() async {
    let engine = ArriqEngine(dryRun: true)
    var s = Settings()
    s.musicEnabled = true
    engine.apply(s)
    engine.turnOff(.speaker)
    await settle(engine) { engine.snapshot.speaker != .working }
    #expect(engine.snapshot.log.map(\.text).contains("dry run: music paused"))
}

@MainActor
@Test func offCancelsAPendingDelayedArrivalRun() async {
    let engine = ArriqEngine(dryRun: true)
    var s = Settings()
    s.lamp = DeviceSetting(enabled: true, delaySeconds: 0)
    engine.apply(s)
    engine.startDevice(.lamp, after: 0.2)  // an arrival run still waiting out its delay
    engine.turnOff(.lamp)
    try? await Task.sleep(nanoseconds: 500_000_000)
    let log = engine.snapshot.log.map(\.text)
    #expect(log.contains("dry run: lamp off · scan"))
    #expect(!log.contains { $0.hasPrefix("dry run: lamp on") })
    #expect(engine.snapshot.lamp == .ready)
}
