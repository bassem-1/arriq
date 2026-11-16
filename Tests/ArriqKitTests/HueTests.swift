import Foundation
import Testing
@testable import ArriqKit

// philips hue: pairing, rooms and lights, state bodies, errors, and the engine routing. dry run, no network.
// every address and key here is a placeholder (192.0.2.x is reserved for documentation).

private func json(_ s: String) -> Data { Data(s.utf8) }

@Test func pairingRepliesAreUnderstood() {
    #expect(HueAPI.parsePair(json(#"[{"success":{"username":"abc123"}}]"#)) == .key("abc123"))
    #expect(HueAPI.parsePair(json(#"[{"error":{"type":101,"description":"link button not pressed"}}]"#)) == .pressButton)
    #expect(HueAPI.parsePair(json(#"[{"error":{"type":7,"description":"Invalid Value"}}]"#)) == .failed("invalid value"))
    #expect(HueAPI.parsePair(json("<html>")) == .failed("not a hue bridge"))
}

@Test func pairRequestNamesArriqAndOnlyTalksToAnIPv4Address() throws {
    let r = try #require(HueAPI.pairRequest(ip: "192.0.2.10"))
    #expect(r.url?.absoluteString == "https://192.0.2.10/api")
    #expect(r.httpMethod == "POST")
    let body = try JSONSerialization.jsonObject(with: try #require(r.httpBody)) as? [String: String]
    #expect(body == ["devicetype": "arriq#mac"])
    #expect(HueAPI.pairRequest(ip: "evil.example.com") == nil)
    #expect(HueAPI.pairRequest(ip: "192.0.2.10/../x") == nil)
}

@Test func bridgeConfigIdentifiesABridge() {
    #expect(HueAPI.parseBridgeName(json(#"{"name":"Philips Hue","bridgeid":"001788FFFE000000"}"#)) == "philips hue")
    #expect(HueAPI.parseBridgeName(json(#"{"name":"router"}"#)) == nil)
}

@Test func roomsAndZonesButNotEntertainmentAreas() {
    let groups = HueAPI.parseGroups(json("""
    {"1":{"name":"Living Room","type":"Room"},"2":{"name":"TV area","type":"Entertainment"},
     "3":{"name":"Upstairs","type":"Zone"},"4":{"type":"Room"}}
    """))
    #expect(groups == [HueTarget(id: "group:1", label: "living room"), HueTarget(id: "group:3", label: "upstairs")])
    let lights = HueAPI.parseLights(json(#"{"7":{"name":"Desk Lamp"},"2":{"name":"Ceiling"}}"#))
    #expect(lights == [HueTarget(id: "light:2", label: "ceiling"), HueTarget(id: "light:7", label: "desk lamp")])
}

@Test func unitConversions() {
    #expect(HueAPI.bri(100) == 254)
    #expect(HueAPI.bri(1) == 3)
    #expect(HueAPI.bri(0) == 1)        // never 0: hue treats bri 0 as an error on some bulbs
    #expect(HueAPI.mired(2700) == 370)
    #expect(HueAPI.mired(9000) == 153) // clamped to the bulb's range
    #expect(HueAPI.mired(2000) == 500)
    #expect(HueAPI.hueValue(0) == 0)
    #expect(HueAPI.hueValue(180) == 32767)
    #expect(HueAPI.hueValue(-90) == HueAPI.hueValue(270))
}

@Test func stateBodiesForOnOffAndLiveAdjust() {
    var s = Settings()
    s.lampBrightness = 50
    s.lampKelvin = 4000
    let on = HueAPI.stateBody(s, on: true)
    #expect(on["on"] as? Bool == true)
    #expect(on["bri"] as? Int == 127)
    #expect(on["ct"] as? Int == 250)
    #expect(on["hue"] == nil)

    s.lampMode = .color
    s.lampHue = 240
    let adjust = HueAPI.stateBody(s, on: nil)
    #expect(adjust["on"] == nil)  // a slider never switches the light on by itself
    #expect(adjust["hue"] as? Int == 43690)
    #expect(adjust["sat"] as? Int == 254)
    #expect(adjust["ct"] == nil)

    #expect(HueAPI.stateBody(s, on: false) as? [String: Bool] == ["on": false])
}

@Test func stateRequestPathsForRoomsAndLights() throws {
    let room = try #require(HueAPI.stateRequest(ip: "192.0.2.10", key: "k", target: "group:3", body: ["on": true]))
    #expect(room.url?.absoluteString == "https://192.0.2.10/api/k/groups/3/action")
    #expect(room.httpMethod == "PUT")
    let light = try #require(HueAPI.stateRequest(ip: "192.0.2.10", key: "k", target: "light:7", body: [:]))
    #expect(light.url?.absoluteString == "https://192.0.2.10/api/k/lights/7/state")
    #expect(HueAPI.stateRequest(ip: "192.0.2.10", key: "k", target: "scene:1", body: [:]) == nil)
    #expect(HueAPI.stateRequest(ip: "192.0.2.10", key: "k", target: "light:", body: [:]) == nil)
    #expect(HueAPI.stateRequest(ip: "192.0.2.10", key: "k", target: "light:1/../../config", body: [:]) == nil)
}

@Test func bridgeErrorsBecomeShortReasons() {
    #expect(HueAPI.parseResult(json(#"[{"success":{"/lights/1/state/on":true}}]"#)) == nil)
    #expect(HueAPI.parseResult(json(#"[{"error":{"type":1,"description":"unauthorized user"}}]"#)) == "key rejected · pair again")
    #expect(HueAPI.parseResult(json(#"[{"error":{"type":3,"description":"resource not available"}}]"#)) == "light not found · pick again")
    #expect(HueAPI.parseResult(json("nope")) == "bridge did not answer")
}

@Test func hueIsNotSetUpUntilBridgeKeyAndLight() {
    var s = Settings()
    s.lampBrand = .hue
    #expect(HueDriver.notSetUpReason(settings: s, keySet: false) == "find your hue bridge")
    s.hueBridgeIP = "192.0.2.10"
    #expect(HueDriver.notSetUpReason(settings: s, keySet: false) == "pair your hue bridge")
    #expect(HueDriver.notSetUpReason(settings: s, keySet: true) == "pick your hue light")
    s.hueTarget = "group:1"
    #expect(HueDriver.notSetUpReason(settings: s, keySet: true) == nil)
}

@Test func hueSettingsDecodeTolerantly() throws {
    let d = try JSONDecoder().decode(Settings.self, from: json("{}"))
    #expect(d.lampBrand == .govee)
    #expect(d.hueBridgeIP == nil)
    let h = try JSONDecoder().decode(Settings.self, from: json(#"{"lampBrand":"hue","hueBridgeIP":" 192.0.2.10 ","hueTarget":"light:2"}"#))
    #expect(h.lampBrand == .hue)
    #expect(h.hueBridgeIP == "192.0.2.10")
    #expect(h.hueTarget == "light:2")
    let junk = try JSONDecoder().decode(Settings.self, from: json(#"{"lampBrand":"ikea","hueBridgeIP":""}"#))
    #expect(junk.lampBrand == .govee)
    #expect(junk.hueBridgeIP == nil)
}

@MainActor
private func settle(until done: () -> Bool) async {
    for _ in 0..<150 where !done() { try? await Task.sleep(nanoseconds: 20_000_000) }
}

@MainActor
@Test func engineRoutesTheLampToHueAndWaitsForSetup() async {
    let engine = ArriqEngine(dryRun: true)
    var s = Settings()
    s.lampBrand = .hue
    engine.apply(s)
    #expect(engine.snapshot.lamp == .notSetUp("find your hue bridge"))
    engine.turnOn(.lamp)
    #expect(engine.snapshot.log.last?.text == "lamp skipped · find your hue bridge")

    s.hueBridgeIP = "192.0.2.10"
    s.hueTarget = "group:1"
    engine.apply(s)
    let paired = await engine.pairHue(ip: "192.0.2.10")  // dry run: no keychain, no bridge
    #expect(paired == .key(""))                          // the key is never handed back to the ui
    #expect(engine.snapshot.hueKeySet)
    #expect(engine.snapshot.lamp == .ready)

    engine.turnOn(.lamp)
    await settle { engine.snapshot.power[.lamp] == true }
    #expect(engine.snapshot.log.map(\.text).contains("dry run: hue on · group:1"))
    engine.turnOff(.lamp)
    await settle { engine.snapshot.power[.lamp] == false }
    #expect(engine.snapshot.log.map(\.text).contains("dry run: hue off · group:1"))
}
